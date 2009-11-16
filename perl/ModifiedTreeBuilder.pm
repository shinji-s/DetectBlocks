package ModifiedTreeBuilder;

# $Id$

require HTML::TreeBuilder;
@ISA=qw(HTML::TreeBuilder);

#---------------------------------------------------------------------------
# Make a 'DEBUG' constant...

BEGIN {
  # We used to have things like
  #  print $indent, "lalala" if $Debug;
  # But there were an awful lot of having to evaluate $Debug's value.
  # If we make that depend on a constant, like so:
  #   sub DEBUG () { 1 } # or whatever value.
  #   ...
  #   print $indent, "lalala" if DEBUG;
  # Which at compile-time (thru the miracle of constant folding) turns into:
  #   print $indent, "lalala";
  # or, if DEBUG is a constant with a true value, then that print statement
  # is simply optimized away, and doesn't appear in the target code at all.
  # If you don't believe me, run:
  #    perl -MO=Deparse,-uHTML::TreeBuilder -e 'BEGIN { \
  #      $HTML::TreeBuilder::DEBUG = 4}  use HTML::TreeBuilder'
  # and see for yourself (substituting whatever value you want for $DEBUG
  # there).

  if(defined &DEBUG) {
    # Already been defined!  Do nothing.
  } elsif($] < 5.00404) {
    # Grudgingly accomodate ancient (pre-constant) versions.
    eval 'sub DEBUG { $Debug } ';
  } elsif(!$DEBUG) {
    eval 'sub DEBUG () {0}';  # Make it a constant.
  } elsif($DEBUG =~ m<^\d+$>s) {
    eval 'sub DEBUG () { ' . $DEBUG . ' }';  # Make THAT a constant.
  } else { # WTF?
    warn "Non-numeric value \"$DEBUG\" in \$HTML::Element::DEBUG";
    eval 'sub DEBUG () { $DEBUG }'; # I guess.
  }
}

#---------------------------------------------------------------------------

sub new { # constructor!
  my $class = shift;
  $class = ref($class) || $class;

  my $self = HTML::Element->new('html');  # Initialize HTML::Element part
  {
    # A hack for certain strange versions of Parser:
##############
    my $other_self = HTML::Parser->new( api_version => 3,
           start_h => [\&start, "self, tagname, offset, attr, attrseq, text"],
           end_h   => [\&end,   "self, tagname, offset, text"],
           text_h   => [\&text,   "self, text, offset, is_cdata"]
           );
##############

    %$self = (%$self, %$other_self);              # copy fields
      # Yes, multiple inheritance is messy.  Kids, don't try this at home.
    bless $other_self, "HTML::TreeBuilder::_hideyhole";
      # whack it out of the HTML::Parser class, to avoid the destructor
  }

  # The root of the tree is special, as it has these funny attributes,
  # and gets reblessed into this class.

  # Initialize parser settings
  # $self->{'_implicit_tags'}  = 1;
  $self->{'_implicit_body_p_tag'} = 0;
    # If true, trying to insert text, or any of %isPhraseMarkup right
    #  under 'body' will implicate a 'p'.  If false, will just go there.

  $self->{'_tighten'} = 1;
    # whether ignorable WS in this tree should be deleted

  $self->{'_implicit'} = 1;  # to delete, once we find a real open-"html" tag

  $self->{'_element_class'}      = 'HTML::Element';
  $self->{'_ignore_unknown'}     = 1;
  $self->{'_ignore_text'}        = 0;
  $self->{'_warn'}               = 0;
  $self->{'_no_space_compacting'}= 0;
  $self->{'_store_comments'}     = 0;
  $self->{'_store_declarations'} = 1;
  $self->{'_store_pis'}          = 0;
  $self->{'_p_strict'} = 0;
  
  # Parse attributes passed in as arguments
  if(@_) {
    my %attr = @_;
    for (keys %attr) {
      $self->{"_$_"} = $attr{$_};
    }
  }

  # rebless to our class
  bless $self, $class;

  $self->{'_element_count'} = 1;
    # undocumented, informal, and maybe not exactly correct

  $self->{'_head'} = $self->insert_element('head',1);
  $self->{'_pos'} = undef; # pull it back up
  $self->{'_body'} = $self->insert_element('body',1);
  $self->{'_pos'} = undef; # pull it back up again

  return $self;
}

#==========================================================================

sub _elem # universal accessor...
{
  my($self, $elem, $val) = @_;
  my $old = $self->{$elem};
  $self->{$elem} = $val if defined $val;
  return $old;
}

# accessors....
sub implicit_tags  { shift->_elem('_implicit_tags',  @_); }
sub implicit_body_p_tag  { shift->_elem('_implicit_body_p_tag',  @_); }
sub p_strict       { shift->_elem('_p_strict',  @_); }
sub no_space_compacting { shift->_elem('_no_space_compacting', @_); }
sub ignore_unknown { shift->_elem('_ignore_unknown', @_); }
sub ignore_text    { shift->_elem('_ignore_text',    @_); }
sub ignore_ignorable_whitespace  { shift->_elem('_tighten',    @_); }
sub store_comments { shift->_elem('_store_comments', @_); }
sub store_declarations { shift->_elem('_store_declarations', @_); }
sub store_pis      { shift->_elem('_store_pis', @_); }
sub warn           { shift->_elem('_warn',           @_); }


#==========================================================================

{
  # To avoid having to rebuild these lists constantly...
  my $_Closed_by_structurals = [qw(p h1 h2 h3 h4 h5 h6 pre textarea)];
  my $indent;

  sub start {
    return if $_[0]{'_stunted'};
    
    # Accept a signal from HTML::Parser for start-tags.
    my($self, $tag, $offset, $attr) = @_;
    # Parser passes more, actually:
    #   $self->start($tag, $attr, $attrseq, $origtext)
    # But we can merrily ignore $attrseq and $origtext.

##############
    $self->{'-offset'}= $offset;
    $attr->{'-offset'}= $offset;
##############

    if($tag eq 'x-html') {
      print "Ignoring open-x-html tag.\n" if DEBUG;
      # inserted by some lame code-generators.
      return;    # bypass tweaking.
    }
   
    $tag =~ s{/$}{}s;  # So <b/> turns into <b>.  Silently forgive.
    
    unless($tag =~ m/^[-_a-zA-Z0-9:%]+$/s) {
      DEBUG and print "Start-tag name $tag is no good.  Skipping.\n";
      return;
      # This avoids having Element's new() throw an exception.
    }

    my $ptag = (
                my $pos  = $self->{'_pos'} || $self
               )->{'_tag'};
    my $already_inserted;
    #my($indent);
    if(DEBUG) {
      # optimization -- don't figure out indenting unless we're in debug mode
      my @lineage = $pos->lineage;
      $indent = '  ' x (1 + @lineage);
      print
        $indent, "Proposing a new \U$tag\E under ",
        join('/', map $_->{'_tag'}, reverse($pos, @lineage)) || 'Root',
        ".\n";
    #} else {
    #  $indent = ' ';
    }
    
    #print $indent, "POS: $pos ($ptag)\n" if DEBUG > 2;
    # $attr = {%$attr};

    foreach my $k (keys %$attr) {
      # Make sure some stooge doesn't have "<span _content='pie'>".
      # That happens every few million Web pages.
      $attr->{' ' . $k} = delete $attr->{$k}
       if length $k and substr($k,0,1) eq '_';
      # Looks bad, but is fine for round-tripping.
    }
    
    my $e =
     ($self->{'_element_class'} || 'HTML::Element')->new($tag, %$attr);
     # Make a new element object.
     # (Only rarely do we end up just throwing it away later in this call.)
     
    # Some prep -- custom messiness for those damned tables, and strict P's.
    if($self->{'_implicit_tags'}) {  # wallawallawalla!
      
      unless($HTML::TreeBuilder::isTableElement{$tag}) {
        if ($ptag eq 'table') {
          print $indent,
            " * Phrasal \U$tag\E right under TABLE makes implicit TR and TD\n"
           if DEBUG > 1;
          $self->insert_element('tr', 1);
          $pos = $self->insert_element('td', 1); # yes, needs updating
        } elsif ($ptag eq 'tr') {
          print $indent,
            " * Phrasal \U$tag\E right under TR makes an implicit TD\n"
           if DEBUG > 1;
          $pos = $self->insert_element('td', 1); # yes, needs updating
        }
        $ptag = $pos->{'_tag'}; # yes, needs updating
      }
       # end of table-implication block.
      
      
      # Now maybe do a little dance to enforce P-strictness.
      # This seems like it should be integrated with the big
      # "ALL HOPE..." block, further below, but that doesn't
      # seem feasable.
      if(
        $self->{'_p_strict'}
        and $HTML::TreeBuilder::isKnown{$tag}
        and not $HTML::Tagset::is_Possible_Strict_P_Content{$tag}
      ) {
        my $here = $pos;
        my $here_tag = $ptag;
        while(1) {
          if($here_tag eq 'p') {
            print $indent,
              " * Inserting $tag closes strict P.\n" if DEBUG > 1;
            $self->end(\q{p});
             # NB: same as \'q', but less confusing to emacs cperl-mode
            last;
          }
          
          #print("Lasting from $here_tag\n"),
          last if
            $HTML::TreeBuilder::isKnown{$here_tag}
            and not $HTML::Tagset::is_Possible_Strict_P_Content{$here_tag};
           # Don't keep looking up the tree if we see something that can't
           #  be strict-P content.
          
          $here_tag = ($here = $here->{'_parent'} || last)->{'_tag'};
        }# end while
        $ptag = ($pos = $self->{'_pos'} || $self)->{'_tag'}; # better update!
      }
       # end of strict-p block.
    }
    
    # And now, get busy...
    #----------------------------------------------------------------------
    if (!$self->{'_implicit_tags'}) {  # bimskalabim
        # do nothing
        print $indent, " * _implicit_tags is off.  doing nothing\n"
         if DEBUG > 1;

    #----------------------------------------------------------------------
    } elsif ($HTML::TreeBuilder::isHeadOrBodyElement{$tag}) {
        if ($pos->is_inside('body')) { # all is well
          print $indent,
            " * ambilocal element \U$tag\E is fine under BODY.\n"
           if DEBUG > 1;
        } elsif ($pos->is_inside('head')) {
          print $indent,
            " * ambilocal element \U$tag\E is fine under HEAD.\n"
           if DEBUG > 1;
        } else {
          # In neither head nor body!  mmmmm... put under head?
          
          if ($ptag eq 'html') { # expected case
            # TODO?? : would there ever be a case where _head would be
            #  absent from a tree that would ever be accessed at this
            #  point?
            die "Where'd my head go?" unless ref $self->{'_head'};
            if ($self->{'_head'}{'_implicit'}) {
              print $indent,
                " * ambilocal element \U$tag\E makes an implicit HEAD.\n"
               if DEBUG > 1;
              # or rather, points us at it.
              $self->{'_pos'} = $self->{'_head'}; # to insert under...
            } else {
              $self->warning(
                "Ambilocal element <$tag> not under HEAD or BODY!?");
              # Put it under HEAD by default, I guess
              $self->{'_pos'} = $self->{'_head'}; # to insert under...
            }
            
          } else { 
            # Neither under head nor body, nor right under html... pass thru?
            $self->warning(
             "Ambilocal element <$tag> neither under head nor body, nor right under html!?");
          }
        }

    #----------------------------------------------------------------------
    } elsif ($HTML::TreeBuilder::isBodyElement{$tag}) {
        
        # Ensure that we are within <body>
        if($ptag eq 'body') {
            # We're good.
        } elsif($HTML::TreeBuilder::isBodyElement{$ptag}  # glarg
          and not $HTML::TreeBuilder::isHeadOrBodyElement{$ptag}
        ) {
            # Special case: Save ourselves a call to is_inside further down.
            # If our $ptag is an isBodyElement element (but not an
            # isHeadOrBodyElement element), then we must be under body!
            print $indent, " * Inferring that $ptag is under BODY.\n",
             if DEBUG > 3;
            # I think this and the test for 'body' trap everything
            # bodyworthy, except the case where the parent element is
            # under an unknown element that's a descendant of body.
        } elsif ($pos->is_inside('head')) {
            print $indent,
              " * body-element \U$tag\E minimizes HEAD, makes implicit BODY.\n"
             if DEBUG > 1;
            $ptag = (
              $pos = $self->{'_pos'} = $self->{'_body'} # yes, needs updating
                || die "Where'd my body go?"
            )->{'_tag'}; # yes, needs updating
        } elsif (! $pos->is_inside('body')) {
            print $indent,
              " * body-element \U$tag\E makes implicit BODY.\n"
             if DEBUG > 1;
            $ptag = (
              $pos = $self->{'_pos'} = $self->{'_body'} # yes, needs updating
                || die "Where'd my body go?"
            )->{'_tag'}; # yes, needs updating
        }
         # else we ARE under body, so okay.
        
        
        # Handle implicit endings and insert based on <tag> and position
        # ... ALL HOPE ABANDON ALL YE WHO ENTER HERE ...
        if ($tag eq 'p'  or
            $tag eq 'h1' or $tag eq 'h2' or $tag eq 'h3' or 
            $tag eq 'h4' or $tag eq 'h5' or $tag eq 'h6' or
            $tag eq 'form'
            # Hm, should <form> really be here?!
        ) {
            # Can't have <p>, <h#> or <form> inside these
            $self->end($_Closed_by_structurals,
                       @HTML::TreeBuilder::p_closure_barriers
                        # used to be just li!
                      );
            
        } elsif ($tag eq 'ol' or $tag eq 'ul' or $tag eq 'dl') {
            # Can't have lists inside <h#> -- in the unlikely
            #  event anyone tries to put them there!
            if (
                $ptag eq 'h1' or $ptag eq 'h2' or $ptag eq 'h3' or 
                $ptag eq 'h4' or $ptag eq 'h5' or $ptag eq 'h6'
            ) {
                $self->end(\$ptag);
            }
            # TODO: Maybe keep closing up the tree until
            #  the ptag isn't any of the above?
            # But anyone that says <h1><h2><ul>...
            #  deserves what they get anyway.
            
        } elsif ($tag eq 'li') { # list item
            # Get under a list tag, one way or another
            unless(
              exists $HTML::TreeBuilder::isList{$ptag} or
              $self->end(\q{*}, keys %HTML::TreeBuilder::isList) #'
            ) { 
              print $indent,
                " * inserting implicit UL for lack of containing ",
                  join('|', keys %HTML::TreeBuilder::isList), ".\n"
               if DEBUG > 1;
              $self->insert_element('ul', 1); 
            }
            
        } elsif ($tag eq 'dt' or $tag eq 'dd') {
            # Get under a DL, one way or another
            unless($ptag eq 'dl' or $self->end(\q{*}, 'dl')) { #'
              print $indent,
                " * inserting implicit DL for lack of containing DL.\n"
               if DEBUG > 1;
              $self->insert_element('dl', 1);
            }
            
        } elsif ($HTML::TreeBuilder::isFormElement{$tag}) {
            if($self->{'_ignore_formies_outside_form'}  # TODO: document this
               and not $pos->is_inside('form')
            ) {
                print $indent,
                  " * ignoring \U$tag\E because not in a FORM.\n"
                  if DEBUG > 1;
                return;    # bypass tweaking.
            }
            if($tag eq 'option') {
                # return unless $ptag eq 'select';
                $self->end(\q{option});
                $ptag = ($self->{'_pos'} || $self)->{'_tag'};
                unless($ptag eq 'select' or $ptag eq 'optgroup') {
                    print $indent, " * \U$tag\E makes an implicit SELECT.\n"
                       if DEBUG > 1;
                    $pos = $self->insert_element('select', 1);
                    # but not a very useful select -- has no 'name' attribute!
                     # is $pos's value used after this?
                }
            }
        } elsif ($HTML::TreeBuilder::isTableElement{$tag}) {
            if(!$pos->is_inside('table')) {
                print $indent, " * \U$tag\E makes an implicit TABLE\n"
                  if DEBUG > 1;
                $self->insert_element('table', 1);
            }

            if($tag eq 'td' or $tag eq 'th') {
                # Get under a tr one way or another
                unless(
                  $ptag eq 'tr' # either under a tr
                  or $self->end(\q{*}, 'tr', 'table') #or we can get under one
                ) {
                    print $indent,
                       " * \U$tag\E under \U$ptag\E makes an implicit TR\n"
                     if DEBUG > 1;
                    $self->insert_element('tr', 1);
                    # presumably pos's value isn't used after this.
                }
            } else {
                $self->end(\$tag, 'table'); #'
            }
            # Hmm, I guess this is right.  To work it out:
            #   tr closes any open tr (limited at a table)
            #   thead closes any open thead (limited at a table)
            #   tbody closes any open tbody (limited at a table)
            #   tfoot closes any open tfoot (limited at a table)
            #   colgroup closes any open colgroup (limited at a table)
            #   col can try, but will always fail, at the enclosing table,
            #     as col is empty, and therefore never open!
            # But!
            #   td closes any open td OR th (limited at a table)
            #   th closes any open th OR td (limited at a table)
            #   ...implementable as "close to a tr, or make a tr"
            
        } elsif ($HTML::TreeBuilder::isPhraseMarkup{$tag}) {
            if($ptag eq 'body' and $self->{'_implicit_body_p_tag'}) {
                print
                  " * Phrasal \U$tag\E right under BODY makes an implicit P\n"
                 if DEBUG > 1;
                $pos = $self->insert_element('p', 1);
                 # is $pos's value used after this?
            }
        }
        # End of implicit endings logic
        
    # End of "elsif ($HTML::TreeBuilder::isBodyElement{$tag}"
    #----------------------------------------------------------------------
    
    } elsif ($HTML::TreeBuilder::isHeadElement{$tag}) {
        if ($pos->is_inside('body')) {
            print $indent, " * head element \U$tag\E found inside BODY!\n"
             if DEBUG;
            $self->warning("Header element <$tag> in body");  # [sic]
        } elsif (!$pos->is_inside('head')) {
            print $indent, " * head element \U$tag\E makes an implicit HEAD.\n"
             if DEBUG > 1;
        } else {
            print $indent,
              " * head element \U$tag\E goes inside existing HEAD.\n"
             if DEBUG > 1;
        }
        $self->{'_pos'} = $self->{'_head'} || die "Where'd my head go?";

    #----------------------------------------------------------------------
    } elsif ($tag eq 'html') {
        if(delete $self->{'_implicit'}) { # first time here
            print $indent, " * good! found the real HTML element!\n"
             if DEBUG > 1;
        } else {
            print $indent, " * Found a second HTML element\n"
             if DEBUG;
            $self->warning("Found a nested <html> element");
        }

        # in either case, migrate attributes to the real element
        for (keys %$attr) {
            $self->attr($_, $attr->{$_});
        }
        $self->{'_pos'} = undef;
        return $self;    # bypass tweaking.

    #----------------------------------------------------------------------
    } elsif ($tag eq 'head') {
        my $head = $self->{'_head'} || die "Where'd my head go?";
        if(delete $head->{'_implicit'}) { # first time here
            print $indent, " * good! found the real HEAD element!\n"
             if DEBUG > 1;
        } else { # been here before
            print $indent, " * Found a second HEAD element\n"
             if DEBUG;
            $self->warning("Found a second <head> element");
        }

        # in either case, migrate attributes to the real element
        for (keys %$attr) {
            $head->attr($_, $attr->{$_});
        }
        return $self->{'_pos'} = $head;    # bypass tweaking.

    #----------------------------------------------------------------------
    } elsif ($tag eq 'body') {
        my $body = $self->{'_body'} || die "Where'd my body go?";
        if(delete $body->{'_implicit'}) { # first time here
            print $indent, " * good! found the real BODY element!\n"
             if DEBUG > 1;
        } else { # been here before
            print $indent, " * Found a second BODY element\n"
             if DEBUG;
            $self->warning("Found a second <body> element");
        }

        # in either case, migrate attributes to the real element
        for (keys %$attr) {
            $body->attr($_, $attr->{$_});
        }
        return $self->{'_pos'} = $body;    # bypass tweaking.

    #----------------------------------------------------------------------
    } elsif ($tag eq 'frameset') {
      if(
        !($self->{'_frameset_seen'}++)   # first frameset seen
        and !$self->{'_noframes_seen'}
          # otherwise it'll be under the noframes already
        and !$self->is_inside('body')
      ) {
	# The following is a bit of a hack.  We don't use the normal
        #  insert_element because 1) we don't want it as _pos, but instead
        #  right under $self, and 2), more importantly, that we don't want
        #  this inserted at the /end/ of $self's content_list, but instead
        #  in the middle of it, specifiaclly right before the body element.
        #
        my $c = $self->{'_content'} || die "Contentless root?";
        my $body = $self->{'_body'} || die "Where'd my BODY go?";
        for(my $i = 0; $i < @$c; ++$i) {
          if($c->[$i] eq $body) {
            splice(@$c, $i, 0, $self->{'_pos'} = $pos = $e);
	    $e->{'_parent'} = $self;
            $already_inserted = 1;
            print $indent, " * inserting 'frameset' right before BODY.\n"
             if DEBUG > 1;
            last;
          }
        }
        die "BODY not found in children of root?" unless $already_inserted;
      }
 
    } elsif ($tag eq 'frame') {
        # Okay, fine, pass thru.
        # Should probably enforce that these should be under a frameset.
        # But hey.  Ditto for enforcing that 'noframes' should be under
        # a 'frameset', as the DTDs say.

    } elsif ($tag eq 'noframes') {
        # This basically assumes there'll be exactly one 'noframes' element
        #  per document.  At least, only the first one gets to have the
        #  body under it.  And if there are no noframes elements, then
        #  the body pretty much stays where it is.  Is that ever a problem?
        if($self->{'_noframes_seen'}++) {
          print $indent, " * ANOTHER noframes element?\n" if DEBUG;
        } else {
          if($pos->is_inside('body')) {
            print $indent, " * 'noframes' inside 'body'.  Odd!\n" if DEBUG;
            # In that odd case, we /can't/ make body a child of 'noframes',
            # because it's an ancestor of the 'noframes'!
          } else {
            $e->push_content( $self->{'_body'} || die "Where'd my body go?" );
            print $indent, " * Moving body to be under noframes.\n" if DEBUG;
          }
        }

    #----------------------------------------------------------------------
    } else {
        # unknown tag
        if ($self->{'_ignore_unknown'}) {
            print $indent, " * Ignoring unknown tag \U$tag\E\n" if DEBUG;
            $self->warning("Skipping unknown tag $tag");
            return;
        } else {
            print $indent, " * Accepting unknown tag \U$tag\E\n"
              if DEBUG;
        }
    }
    #----------------------------------------------------------------------
     # End of mumbo-jumbo
    
    
    print
      $indent, "(Attaching ", $e->{'_tag'}, " under ",
      ($self->{'_pos'} || $self)->{'_tag'}, ")\n"
        # because if _pos isn't defined, it goes under self
     if DEBUG;
    
    
    # The following if-clause is to delete /some/ ignorable whitespace
    #  nodes, as we're making the tree.
    # This'd be a node we'd catch later anyway, but we might as well
    #  nip it in the bud now.
    # This doesn't catch /all/ deletable WS-nodes, so we do have to call
    #  the tightener later to catch the rest.

    if($self->{'_tighten'} and !$self->{'_ignore_text'}) {  # if tightenable
      my($sibs, $par);
      if(
         ($sibs = ( $par = $self->{'_pos'} || $self )->{'_content'})
         and @$sibs  # parent already has content
         and !ref($sibs->[-1])  # and the last one there is a text node
         and $sibs->[-1] !~ m<[^\n\r\f\t ]>s  # and it's all whitespace

         and (  # one of these has to be eligible...
               $HTML::TreeBuilder::canTighten{$tag}
               or
               (
                 (@$sibs == 1)
                   ? # WS is leftmost -- so parent matters
                     $HTML::TreeBuilder::canTighten{$par->{'_tag'}}
                   : # WS is after another node -- it matters
                     (ref $sibs->[-2]
                      and $HTML::TreeBuilder::canTighten{$sibs->[-2]{'_tag'}}
                     )
               )
             )

         and !$par->is_inside('pre', 'xmp', 'textarea', 'plaintext')
                # we're clear
      ) {
        pop @$sibs;
        print $indent, "Popping a preceding all-WS node\n" if DEBUG;
      }
    }
    
    $self->insert_element($e) unless $already_inserted;

    if(DEBUG) {
      if($self->{'_pos'}) {
        print
          $indent, "(Current lineage of pos:  \U$tag\E under ",
          join('/',
            reverse(
              # $self->{'_pos'}{'_tag'},  # don't list myself!
              $self->{'_pos'}->lineage_tag_names
            )
          ),
          ".)\n";
      } else {
        print $indent, "(Pos points nowhere!?)\n";
      }
    }

    unless(($self->{'_pos'} || '') eq $e) {
      # if it's an empty element -- i.e., if it didn't change the _pos
      &{  $self->{"_tweak_$tag"}
          ||  $self->{'_tweak_*'}
          || return $e
      }(map $_,   $e, $tag, $self); # make a list so the user can't clobber
    }

    return $e;
  }
}

#==========================================================================

{
  my $indent;

  sub end {
    return if $_[0]{'_stunted'};
    
    # Either: Acccept an end-tag signal from HTML::Parser
    # Or: Method for closing currently open elements in some fairly complex
    #  way, as used by other methods in this class.
    my($self, $tag, $offset, @stop) = @_;

    # Dumpvalue->new->dumpValue($attr);
    # print $offset,"\n";

    if($tag eq 'x-html') {
      print "Ignoring close-x-html tag.\n" if DEBUG;
      # inserted by some lame code-generators.
      return;
    }

    unless(ref($tag) or $tag =~ m/^[-_a-zA-Z0-9:%]+$/s) {
      DEBUG and print "End-tag name $tag is no good.  Skipping.\n";
      return;
      # This avoids having Element's new() throw an exception.
    }

    # This method accepts two calling formats:
    #  1) from Parser:  $self->end('tag_name', 'origtext')
    #        in which case we shouldn't mistake origtext as a blocker tag
    #  2) from myself:  $self->end(\q{tagname1}, 'blk1', ... )
    #     from myself:  $self->end(['tagname1', 'tagname2'], 'blk1',  ... )
    
    # End the specified tag, but don't move above any of the blocker tags.
    # The tag can also be a reference to an array.  Terminate the first
    # tag found.
    
    my $ptag = ( my $p = $self->{'_pos'} || $self )->{'_tag'};
     # $p and $ptag are sort-of stratch
    
    if(ref($tag)) {
      # First param is a ref of one sort or another --
      #  THE CALL IS COMING FROM INSIDE THE HOUSE!
      $tag = $$tag if ref($tag) eq 'SCALAR';
       # otherwise it's an arrayref.
    } else {
      # the call came from Parser -- just ignore origtext
      @stop = ();
    }
    
    #my($indent);
    if(DEBUG) {
      # optimization -- don't figure out depth unless we're in debug mode
      my @lineage_tags = $p->lineage_tag_names;
      $indent = '  ' x (1 + @lineage_tags);
      
      # now announce ourselves
      print $indent, "Ending ",
        ref($tag) ? ('[', join(' ', @$tag ), ']') : "\U$tag\E",
        scalar(@stop) ? (" no higher than [", join(' ', @stop), "]" )
          : (), ".\n"
      ;
      
      print $indent, " (Current lineage: ", join('/', @lineage_tags), ".)\n"
       if DEBUG > 1;
       
      if(DEBUG > 3) {
        #my(
        # $package, $filename, $line, $subroutine,
        # $hasargs, $wantarray, $evaltext, $is_require) = caller;
        print $indent,
          " (Called from ", (caller(1))[3], ' line ', (caller(1))[2],
          ")\n";
      }
      
    #} else {
    #  $indent = ' ';
    }
    # End of if DEBUG
    
    # Now actually do it
    my @to_close;
    if($tag eq '*') {
      # Special -- close everything up to (but not including) the first
      #  limiting tag, or return if none found.  Somewhat of a special case.
     PARENT:
      while (defined $p) {
        $ptag = $p->{'_tag'};
        print $indent, " (Looking at $ptag.)\n" if DEBUG > 2;
        for (@stop) {
          if($ptag eq $_) {
            print $indent, " (Hit a $_; closing everything up to here.)\n"
             if DEBUG > 2;
            last PARENT;
          }
        }
        push @to_close, $p;
        $p = $p->{'_parent'}; # no match so far? keep moving up
        print
          $indent, 
          " (Moving on up to ", $p ? $p->{'_tag'} : 'nil', ")\n"
         if DEBUG > 1;
        ;
      }
      unless(defined $p) { # We never found what we were looking for.
        print $indent, " (We never found a limit.)\n" if DEBUG > 1;
        return;
      }
      #print
      #   $indent,
      #   " (To close: ", join('/', map $_->tag, @to_close), ".)\n"
      #  if DEBUG > 4;
      
      # Otherwise update pos and fall thru.
      $self->{'_pos'} = $p;
    } elsif (ref $tag) {
      # Close the first of any of the matching tags, giving up if you hit
      #  any of the stop-tags.
     PARENT:
      while (defined $p) {
        $ptag = $p->{'_tag'};
        print $indent, " (Looking at $ptag.)\n" if DEBUG > 2;
        for (@$tag) {
          if($ptag eq $_) {
            print $indent, " (Closing $_.)\n" if DEBUG > 2;
            last PARENT;
          }
        }
        for (@stop) {
          if($ptag eq $_) {
            print $indent, " (Hit a limiting $_ -- bailing out.)\n"
             if DEBUG > 1;
            return; # so it was all for naught
          }
        }
        push @to_close, $p;
        $p = $p->{'_parent'};
      }
      return unless defined $p; # We went off the top of the tree.
      # Otherwise specified element was found; set pos to its parent.
      push @to_close, $p;
      $self->{'_pos'} = $p->{'_parent'};
    } else {
      # Close the first of the specified tag, giving up if you hit
      #  any of the stop-tags.
      while (defined $p) {
        $ptag = $p->{'_tag'};
        print $indent, " (Looking at $ptag.)\n" if DEBUG > 2;
        if($ptag eq $tag) {
          print $indent, " (Closing $tag.)\n" if DEBUG > 2;
          last;
        }
        for (@stop) {
          if($ptag eq $_) {
            print $indent, " (Hit a limiting $_ -- bailing out.)\n"
             if DEBUG > 1;
            return; # so it was all for naught
          }
        }
        push @to_close, $p;
        $p = $p->{'_parent'};
      }
      return unless defined $p; # We went off the top of the tree.
      # Otherwise specified element was found; set pos to its parent.
      push @to_close, $p;
      $self->{'_pos'} = $p->{'_parent'};
    }
    
    $self->{'_pos'} = undef if $self eq ($self->{'_pos'} || '');
    print $indent, "(Pos now points to ",
      $self->{'_pos'} ? $self->{'_pos'}{'_tag'} : '???', ".)\n"
     if DEBUG > 1;
    
    ### EXPENSIVE, because has to check that it's not under a pre
    ### or a CDATA-parent.  That's one more method call per end()!
    ### Might as well just do this at the end of the tree-parse, I guess,
    ### at which point we'd be parsing top-down, and just not traversing
    ### under pre's or CDATA-parents.
    ##
    ## Take this opportunity to nix any terminal whitespace nodes.
    ## TODO: consider whether this (plus the logic in start(), above)
    ## would ever leave any WS nodes in the tree.
    ## If not, then there's no reason to have eof() call
    ## delete_ignorable_whitespace on the tree, is there?
    ##
    #if(@to_close and $self->{'_tighten'} and !$self->{'_ignore_text'} and
    #  ! $to_close[-1]->is_inside('pre', keys %HTML::Tagset::isCDATA_Parent)
    #) {  # if tightenable
    #  my($children, $e_tag);
    #  foreach my $e (reverse @to_close) { # going top-down
    #    last if 'pre' eq ($e_tag = $e->{'_tag'}) or
    #     $HTML::Tagset::isCDATA_Parent{$e_tag};
    #    
    #    if(
    #      $children = $e->{'_content'}
    #      and @$children      # has children
    #      and !ref($children->[-1])
    #      and $children->[-1] =~ m<^\s+$>s # last node is all-WS
    #      and
    #        (
    #         # has a tightable parent:
    #         $HTML::TreeBuilder::canTighten{ $e_tag }
    #         or
    #          ( # has a tightenable left sibling:
    #            @$children > 1 and 
    #            ref($children->[-2])
    #            and $HTML::TreeBuilder::canTighten{ $children->[-2]{'_tag'} }
    #          )
    #        )
    #    ) {
    #      pop @$children;
    #      #print $indent, "Popping a terminal WS node from ", $e->{'_tag'},
    #      #  " (", $e->address, ") while exiting.\n" if DEBUG;
    #    }
    #  }
    #}
    
    
    foreach my $e (@to_close) {
      # Call the applicable callback, if any
      $ptag = $e->{'_tag'};
      &{  $self->{"_tweak_$ptag"}
          ||  $self->{'_tweak_*'}
          || next
      }(map $_,   $e, $ptag, $self);
      print $indent, "Back from tweaking.\n" if DEBUG;
      last if $self->{'_stunted'}; # in case one of the handlers called stunt
    }
    return @to_close;
  }
}

#==========================================================================
{
  my($indent, $nugget);

  sub text {
    return if $_[0]{'_stunted'};
    
  # Accept a "here's a text token" signal from HTML::Parser.
    my($self, $text, $offset, $is_cdata) = @_;
      # the >3.0 versions of Parser may pass a cdata node.
      # Thanks to Gisle Aas for pointing this out.
    
    # print $offset,"\n";

    return unless length $text; # I guess that's always right
    
    my $ignore_text = $self->{'_ignore_text'};
    my $no_space_compacting = $self->{'_no_space_compacting'};
    
    my $pos = $self->{'_pos'} || $self;
    
    HTML::Entities::decode($text)
     unless $ignore_text || $is_cdata
      || $HTML::Tagset::isCDATA_Parent{$pos->{'_tag'}};
    
    #my($indent, $nugget);
    if(DEBUG) {
      # optimization -- don't figure out depth unless we're in debug mode
      my @lineage_tags = $pos->lineage_tag_names;
      $indent = '  ' x (1 + @lineage_tags);
      
      $nugget = (length($text) <= 25) ? $text : (substr($text,0,25) . '...');
      $nugget =~ s<([\x00-\x1F])>
                 <'\\x'.(unpack("H2",$1))>eg;
      print
        $indent, "Proposing a new text node ($nugget) under ",
        join('/', reverse($pos->{'_tag'}, @lineage_tags)) || 'Root',
        ".\n";
      
    #} else {
    #  $indent = ' ';
    }
    
    
    my $ptag;
    if ($HTML::Tagset::isCDATA_Parent{$ptag = $pos->{'_tag'}}
        #or $pos->is_inside('pre')
        or $pos->is_inside('pre', 'textarea')
    ) {
        return if $ignore_text;
        $pos->push_content($text);
    } else {
        # return unless $text =~ /\S/;  # This is sometimes wrong

        if (!$self->{'_implicit_tags'} || $text !~ /[^\n\r\f\t ]/) {
            # don't change anything
        } elsif ($ptag eq 'head' or $ptag eq 'noframes') {
            if($self->{'_implicit_body_p_tag'}) {
              print $indent,
                " * Text node under \U$ptag\E closes \U$ptag\E, implicates BODY and P.\n"
               if DEBUG > 1;
              $self->end(\$ptag);
              $pos =
                $self->{'_body'}
                ? ($self->{'_pos'} = $self->{'_body'}) # expected case
                : $self->insert_element('body', 1);
              $pos = $self->insert_element('p', 1);
            } else {
              print $indent,
                " * Text node under \U$ptag\E closes, implicates BODY.\n"
               if DEBUG > 1;
              $self->end(\$ptag);
              $pos =
                $self->{'_body'}
                ? ($self->{'_pos'} = $self->{'_body'}) # expected case
                : $self->insert_element('body', 1);
            }
        } elsif ($ptag eq 'html') {
            if($self->{'_implicit_body_p_tag'}) {
              print $indent,
                " * Text node under HTML implicates BODY and P.\n"
               if DEBUG > 1;
              $pos =
                $self->{'_body'}
                ? ($self->{'_pos'} = $self->{'_body'}) # expected case
                : $self->insert_element('body', 1);
              $pos = $self->insert_element('p', 1);
            } else {
              print $indent,
                " * Text node under HTML implicates BODY.\n"
               if DEBUG > 1;
              $pos =
                $self->{'_body'}
                ? ($self->{'_pos'} = $self->{'_body'}) # expected case
                : $self->insert_element('body', 1);
              #print "POS is $pos, ", $pos->{'_tag'}, "\n";
            }
        } elsif ($ptag eq 'body') {
            if($self->{'_implicit_body_p_tag'}) {
              print $indent,
                " * Text node under BODY implicates P.\n"
               if DEBUG > 1;
              $pos = $self->insert_element('p', 1);
            }
        } elsif ($ptag eq 'table') {
            print $indent,
              " * Text node under TABLE implicates TR and TD.\n"
             if DEBUG > 1;
            $self->insert_element('tr', 1);
            $pos = $self->insert_element('td', 1);
             # double whammy!
        } elsif ($ptag eq 'tr') {
            print $indent,
              " * Text node under TR implicates TD.\n"
             if DEBUG > 1;
            $pos = $self->insert_element('td', 1);
        }
##############
#        $text .= "/" . $offset;
##############

        # elsif (
        #       # $ptag eq 'li'   ||
        #       # $ptag eq 'dd'   ||
        #         $ptag eq 'form') {
        #    $pos = $self->insert_element('p', 1);
        #}
        
        
        # Whatever we've done above should have had the side
        # effect of updating $self->{'_pos'}
        
                
        #print "POS is now $pos, ", $pos->{'_tag'}, "\n";
        
        return if $ignore_text;
        $text =~ s/[\n\r\f\t ]+/ /g  # canonical space
            unless $no_space_compacting ;

        print
          $indent, " (Attaching text node ($nugget) under ",
          # was: $self->{'_pos'} ? $self->{'_pos'}{'_tag'} : $self->{'_tag'},
          $pos->{'_tag'},
          ").\n"
         if DEBUG > 1;
        
        $pos->push_content($text);
    }
    
    &{ $self->{'_tweak_~text'} || return }($text, $pos, $pos->{'_tag'} . '');
     # Note that this is very exceptional -- it doesn't fall back to
     #  _tweak_*, and it gives its tweak different arguments.
    return;
  }
}

#==========================================================================

# TODO: test whether comment(), declaration(), and process(), do the right
#  thing as far as tightening and whatnot.
# Also, currently, doctypes and comments that appear before head or body
#  show up in the tree in the wrong place.  Something should be done about
#  this.  Tricky.  Maybe this whole business of pre-making the body and
#  whatnot is wrong.

sub comment {
  return if $_[0]{'_stunted'};
  # Accept a "here's a comment" signal from HTML::Parser.

  my($self, $text) = @_;
  my $pos = $self->{'_pos'} || $self;
  return unless $self->{'_store_comments'}
     || $HTML::Tagset::isCDATA_Parent{ $pos->{'_tag'} };
  
  if(DEBUG) {
    my @lineage_tags = $pos->lineage_tag_names;
    my $indent = '  ' x (1 + @lineage_tags);
    
    my $nugget = (length($text) <= 25) ? $text : (substr($text,0,25) . '...');
    $nugget =~ s<([\x00-\x1F])>
                 <'\\x'.(unpack("H2",$1))>eg;
    print
      $indent, "Proposing a Comment ($nugget) under ",
      join('/', reverse($pos->{'_tag'}, @lineage_tags)) || 'Root',
      ".\n";
  }

  (my $e = (
    $self->{'_element_class'} || 'HTML::Element'
   )->new('~comment'))->{'text'} = $text;
  $pos->push_content($e);
  ++($self->{'_element_count'});

  &{  $self->{'_tweak_~comment'}
      || $self->{'_tweak_*'}
      || return $e
   }(map $_,   $e, '~comment', $self);
  
  return $e;
}

sub declaration {
  return if $_[0]{'_stunted'};
  # Accept a "here's a markup declaration" signal from HTML::Parser.

  my($self, $text) = @_;
  my $pos = $self->{'_pos'} || $self;

  if(DEBUG) {
    my @lineage_tags = $pos->lineage_tag_names;
    my $indent = '  ' x (1 + @lineage_tags);

    my $nugget = (length($text) <= 25) ? $text : (substr($text,0,25) . '...');
    $nugget =~ s<([\x00-\x1F])>
                 <'\\x'.(unpack("H2",$1))>eg;
    print
      $indent, "Proposing a Declaration ($nugget) under ",
      join('/', reverse($pos->{'_tag'}, @lineage_tags)) || 'Root',
      ".\n";
  }
  (my $e = (
    $self->{'_element_class'} || 'HTML::Element'
   )->new('~declaration'))->{'text'} = $text;

  $self->{_decl} = $e;
  return $e;
}

#==========================================================================

sub process {
  return if $_[0]{'_stunted'};
  # Accept a "here's a PI" signal from HTML::Parser.

  return unless $_[0]->{'_store_pis'};
  my($self, $text) = @_;
  my $pos = $self->{'_pos'} || $self;
  
  if(DEBUG) {
    my @lineage_tags = $pos->lineage_tag_names;
    my $indent = '  ' x (1 + @lineage_tags);
    
    my $nugget = (length($text) <= 25) ? $text : (substr($text,0,25) . '...');
    $nugget =~ s<([\x00-\x1F])>
                 <'\\x'.(unpack("H2",$1))>eg;
    print
      $indent, "Proposing a PI ($nugget) under ",
      join('/', reverse($pos->{'_tag'}, @lineage_tags)) || 'Root',
      ".\n";
  }
  (my $e = (
    $self->{'_element_class'} || 'HTML::Element'
   )->new('~pi'))->{'text'} = $text;
  $pos->push_content($e);
  ++($self->{'_element_count'});

  &{  $self->{'_tweak_~pi'}
      || $self->{'_tweak_*'}
      || return $e
   }(map $_,   $e, '~pi', $self);
  
  return $e;
}


#--------------------------------------------------------------------------
1;

__END__

=head1 NAME

HTML::TreeBuilder - Parser that builds a HTML syntax tree

=head1 SYNOPSIS

  foreach my $file_name (@ARGV) {
    my $tree = HTML::TreeBuilder->new; # empty tree
    $tree->parse_file($file_name);
    print "Hey, here's a dump of the parse tree of $file_name:\n";
    $tree->dump; # a method we inherit from HTML::Element
    print "And here it is, bizarrely rerendered as HTML:\n",
      $tree->as_HTML, "\n";
    
    # Now that we're done with it, we must destroy it.
    $tree = $tree->delete;
  }

=head1 DESCRIPTION

(This class is part of the L<HTML::Tree|HTML::Tree> dist.)

This class is for HTML syntax trees that get built out of HTML
source.  The way to use it is to:

1. start a new (empty) HTML::TreeBuilder object,

2. then use one of the methods from HTML::Parser (presumably with
$tree->parse_file($filename) for files, or with
$tree->parse($document_content) and $tree->eof if you've got
the content in a string) to parse the HTML
document into the tree $tree.

(You can combine steps 1 and 2 with the "new_from_file" or
"new_from_content" methods.)

2b. call $root-E<gt>elementify() if you want.

3. do whatever you need to do with the syntax tree, presumably
involving traversing it looking for some bit of information in it,

4. and finally, when you're done with the tree, call $tree->delete() to
erase the contents of the tree from memory.  This kind of thing
usually isn't necessary with most Perl objects, but it's necessary for
TreeBuilder objects.  See L<HTML::Element|HTML::Element> for a more verbose
explanation of why this is the case.

=head1 METHODS AND ATTRIBUTES

Objects of this class inherit the methods of both HTML::Parser and
HTML::Element.  The methods inherited from HTML::Parser are used for
building the HTML tree, and the methods inherited from HTML::Element
are what you use to scrutinize the tree.  Besides this
(HTML::TreeBuilder) documentation, you must also carefully read the
HTML::Element documentation, and also skim the HTML::Parser
documentation -- probably only its parse and parse_file methods are of
interest.

Most of the following methods native to HTML::TreeBuilder control how
parsing takes place; they should be set I<before> you try parsing into
the given object.  You can set the attributes by passing a TRUE or
FALSE value as argument.  E.g., $root->implicit_tags returns the current
setting for the implicit_tags option, $root->implicit_tags(1) turns that
option on, and $root->implicit_tags(0) turns it off.

=over 4

=item $root = HTML::TreeBuilder->new_from_file(...)

This "shortcut" constructor merely combines constructing a new object
(with the "new" method, below), and calling $new->parse_file(...) on
it.  Returns the new object.  Note that this provides no way of
setting any parse options like store_comments (for that, call new, and
then set options, before calling parse_file).  See the notes (below)
on parameters to parse_file.

=item $root = HTML::TreeBuilder->new_from_content(...)

This "shortcut" constructor merely combines constructing a new object
(with the "new" method, below), and calling for(...){$new->parse($_)}
and $new->eof on it.  Returns the new object.  Note that this provides
no way of setting any parse options like store_comments (for that,
call new, and then set options, before calling parse_file).  Example
usages: HTML::TreeBuilder->new_from_content(@lines), or
HTML::TreeBuilder->new_from_content($content)

=item $root = HTML::TreeBuilder->new()

This creates a new HTML::TreeBuilder object.  This method takes no
attributes.

=item $root->parse_file(...)

[An important method inherited from L<HTML::Parser|HTML::Parser>, which
see.  Current versions of HTML::Parser can take a filespec, or a
filehandle object, like *FOO, or some object from class IO::Handle,
IO::File, IO::Socket) or the like.
I think you should check that a given file exists I<before> calling 
$root->parse_file($filespec).]

=item $root->parse(...)

[A important method inherited from L<HTML::Parser|HTML::Parser>, which
see.  See the note below for $root->eof().]

=item $root->eof()

This signals that you're finished parsing content into this tree; this
runs various kinds of crucial cleanup on the tree.  This is called
I<for you> when you call $root->parse_file(...), but not when
you call $root->parse(...).  So if you call
$root->parse(...), then you I<must> call $root->eof()
once you've finished feeding all the chunks to parse(...), and
before you actually start doing anything else with the tree in C<$root>.

=item C<< $root->parse_content(...) >>

Basically a happly alias for C<< $root->parse(...); $root->eof >>.
Takes the exact same arguments as C<< $root->parse() >>.

=item $root->delete()

[An important method inherited from L<HTML::Element|HTML::Element>, which
see.]

=item $root->elementify()

This changes the class of the object in $root from
HTML::TreeBuilder to the class used for all the rest of the elements
in that tree (generally HTML::Element).  Returns $root.

For most purposes, this is unnecessary, but if you call this after
(after!!)
you've finished building a tree, then it keeps you from accidentally
trying to call anything but HTML::Element methods on it.  (I.e., if
you accidentally call C<$root-E<gt>parse_file(...)> on the
already-complete and elementified tree, then instead of charging ahead
and I<wreaking havoc>, it'll throw a fatal error -- since C<$root> is
now an object just of class HTML::Element which has no C<parse_file>
method.

Note that elementify currently deletes all the private attributes of
$root except for "_tag", "_parent", "_content", "_pos", and
"_implicit".  If anyone requests that I change this to leave in yet
more private attributes, I might do so, in future versions.

=item @nodes = $root->guts()

=item $parent_for_nodes = $root->guts()

In list context (as in the first case), this method returns the topmost
non-implicit nodes in a tree.  This is useful when you're parsing HTML
code that you know doesn't expect an HTML document, but instead just
a fragment of an HTML document.  For example, if you wanted the parse
tree for a file consisting of just this:

  <li>I like pie!

Then you would get that with C<< @nodes = $root->guts(); >>.
It so happens that in this case, C<@nodes> will contain just one
element object, representing the "li" node (with "I like pie!" being
its text child node).  However, consider if you were parsing this:

  <hr>Hooboy!<hr>

In that case, C<< $root->guts() >> would return three items:
an element object for the first "hr", a text string "Hooboy!", and
another "hr" element object.

For cases where you want definitely one element (so you can treat it as
a "document fragment", roughly speaking), call C<guts()> in scalar
context, as in C<< $parent_for_nodes = $root->guts() >>. That works like
C<guts()> in list context; in fact, C<guts()> in list context would
have returned exactly one value, and if it would have been an object (as
opposed to a text string), then that's what C<guts> in scalar context
will return.  Otherwise, if C<guts()> in list context would have returned
no values at all, then C<guts()> in scalar context returns undef.  In
all other cases, C<guts()> in scalar context returns an implicit 'div'
element node, with children consisting of whatever nodes C<guts()>
in list context would have returned.  Note that that may detach those
nodes from C<$root>'s tree.

=item @nodes = $root->disembowel()

=item $parent_for_nodes = $root->disembowel()

The C<disembowel()> method works just like the C<guts()> method, except
that disembowel definitively destroys the tree above the nodes that
are returned.  Usually when you want the guts from a tree, you're just
going to toss out the rest of the tree anyway, so this saves you the
bother.  (Remember, "disembowel" means "remove the guts from".)

=item $root->implicit_tags(value)

Setting this attribute to true will instruct the parser to try to
deduce implicit elements and implicit end tags.  If it is false you
get a parse tree that just reflects the text as it stands, which is
unlikely to be useful for anything but quick and dirty parsing.
(In fact, I'd be curious to hear from anyone who finds it useful to
have implicit_tags set to false.)
Default is true.

Implicit elements have the implicit() attribute set.

=item $root->implicit_body_p_tag(value)

This controls an aspect of implicit element behavior, if implicit_tags
is on:  If a text element (PCDATA) or a phrasal element (such as
"E<lt>emE<gt>") is to be inserted under "E<lt>bodyE<gt>", two things
can happen: if implicit_body_p_tag is true, it's placed under a new,
implicit "E<lt>pE<gt>" tag.  (Past DTDs suggested this was the only
correct behavior, and this is how past versions of this module
behaved.)  But if implicit_body_p_tag is false, nothing is implicated
-- the PCDATA or phrasal element is simply placed under
"E<lt>bodyE<gt>".  Default is false.

=item $root->ignore_unknown(value)

This attribute controls whether unknown tags should be represented as
elements in the parse tree, or whether they should be ignored. 
Default is true (to ignore unknown tags.)

=item $root->ignore_text(value)

Do not represent the text content of elements.  This saves space if
all you want is to examine the structure of the document.  Default is
false.

=item $root->ignore_ignorable_whit
