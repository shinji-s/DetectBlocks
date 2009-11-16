#!/opt/PERL/wisdom/bin/perl -w

# $Id$

use strict;
use Encode;
use ModifiedTreeBuilder;
use Unicode::Japanese;

main:{
	my $html = &get_dat("000000000.html");
	my $tree = ModifiedTreeBuilder->new;
	$tree->utf8_mode(1);
	$tree->parse($html);
	$tree->eof;

	my $elm = $tree->find('body');
	my ($error,$parent) = &get_parent_node($elm);
	print $elm->tag . " " . $parent . " " . $elm->{-offset} . "\n";
	&get_all_element($elm);
}

sub get_all_element()
{
	my ($e) = @_;
	my @elements = $e->content_list();
	return if ($#elements < 0);
	for (my $i = 0; $i <= $#elements; $i++) {
		my $elm = $elements[$i];
		if (ref $elm eq "HTML::Element") {
			my ($error,$parent) = &get_parent_node($elm);
			print $elm->tag . " " . $parent . " " . $elm->{-offset} . "\n";
			&get_all_element($elm);
		} else {
			print "[" . $elm . "]\n";
		}
	}
}

sub get_parent_node
{
	my ($e) = @_;
	my $tag;
	eval {$tag = $e->tag;};
	if ($@) {return ("1",$@);}
	my $adr = $e->address();
	my @age = $e->lineage;
	my @ages;
	push(@ages, $tag . ":$adr");
	foreach my $a ( @age ){
		my $name = $a->tag;
		unshift(@ages, $name);
	}
	return (0,join("/",@ages));
}

sub get_dat {
	my ($file) = @_;
	my $dat;
	open F, $file or die;
	while (<F>) {
		$dat .= $_;
	}
	close F;
	return $dat;
}

1;
