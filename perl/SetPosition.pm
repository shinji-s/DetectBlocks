package SetPosition;

use strict;
use utf8;
use Digest::MD5 qw/md5 md5_hex/;
use POSIX;
use Encode;
use Encode::Guess;

use DetectBlocks;


# loopLimit:子プロセスが終了するまで待つ時間の最大値(秒)
our %thisopt = ('proxy'=>'http://proxy.kuins.net:8080/', 'Google_agent'=>1, 'loopLimit'=>30);

# 子プロセスの状態を確認する間隔(秒)
our $interval = 0.5;

our $charCode;


# 位置情報を書き込む
# エラーの場合は-1を返す
sub execAddPosition {

    my ($html, $execpath, $jspath, $opt) = @_;

    unless (-e $execpath && -e $jspath) {
	print "not exist execpath or jspath\n";
	return -1;
    }

    # オプションでsource_urlが指定されている場合、htmlの相対パスを絶対パスにする
    if ($opt->{'source_url'}) {
	$html = &SetPosition::rel_path2abs_path($html, $opt->{'source_url'});
    }

    if (Encode::is_utf8($html)) {
	if ($charCode) {
	    $html = encode($charCode, $html);
	} else {
	    $charCode = Encode::Guess->guess_encoding($html, qw/utf8 shiftjis euc-jp/);
	    if (ref($charCode)) {
		$charCode = $charCode->name;
	    }
	    $html = encode($charCode, $html);
	}
    }
    # 一時ファイル名
    my $cache = 'cache_' . substr(md5_hex($html), 0, 20) . '.html';
    my $returnhtml;

    # charsetがない場合、付与する
#    $html = &SetPosition::setCharset($html);

    # htmlの一時ファイル作成
    open(FILE, ">$cache");
    print FILE $html;
    close(FILE);

    # htmlに位置情報等を書き込む
    # 子プロセスを生成し、htmlに位置情報を書き込む処理を走らせる
    # $loopLimit以上子プロセスが動き続けている場合はkillして-1を返す
    my $pid = fork();
    if ($pid > 0) {
        my $i = 0;
	my $loopLimit = $opt->{'loopLimit'};
        while ($i < $loopLimit) {
            my $status = waitpid($pid, &POSIX::WNOHANG);
            if ($status == 0) {
		select(undef, undef, undef, $interval);
                $i += $interval;
            } elsif ($status > 0) {
		last;
            } else {
		$returnhtml = -1;
		last;
	    }
	    if ($i >= $loopLimit) {
		kill(&POSIX::SIGKILL, $pid);
		waitpid($pid,0);
		$returnhtml = -1;
		last;
	    }
	}
    } elsif ($pid == 0) {
	exec "$execpath",'-j',"$jspath", "$cache", "$cache";
    } else {
	$returnhtml = -1;
    }

    # 位置情報が書き込まれたファイルを文字列にする
    if ($returnhtml != -1) {
	open(FILE, "<$cache");
	while(<FILE>){$returnhtml .= $_;}
	close(FILE);
	unlink($cache);
	$returnhtml = decode(guess_encoding($returnhtml, qw/ascii euc-jp shiftjis 7bit-jis utf8/), $returnhtml);
    }

    return ($returnhtml, $charCode) if ($opt->{'getCharCode'});
    return $returnhtml;
}

# 基本的に外部からはこれを呼び出す
# ファイル、URL、文字列
sub setPosition {

    my ($target, $execpath, $jspath, $opt) = @_;

    while (my ($key, $val) = each(%thisopt)) {
	unless (defined($opt->{$key})) {
	    $opt->{$key} = $val;
	}
    }

    my $html;
    # ローカルのファイルの場合
    if (-e $target) {
	open(FILE, "<" . $target);
	while(<FILE>){$html.=$_;}
	close(FILE);
    }
    # urlの場合
    elsif ($target =~ /^http:\/\//) {
	my $DetectBlocks = new DetectBlocks();
	($html, $target) = $DetectBlocks->Get_Source_String($target, $opt);
    }
    # その他はhtml文字列として扱う場合
    else {
	$html = $target;
    }
    $html = &SetPosition::setCharset($html);

    return &SetPosition::execAddPosition($html, $execpath, $jspath, $opt);
}


# cssとjavascriptが相対パスで指定されている場合、絶対パスに変換する
# 入力はhtmlの文字列
sub rel_path2abs_path {

    my ($html, $url) = @_;

    # typeがcssとjavascriptのタグを収集
    my @elems;
    while($html =~ /<[^<^>]*type\=.text\/(css|javascript)[^<^>]*>/ig) {
	push(@elems, $&);
    }
    while ($html =~ /<[^<^>]*rel\=.stylesheet[^<^>]*>/ig) {
	push(@elems, $&);
    }
    # hrefかsrcの値を絶対パスにして置換する
    foreach my $elemText (@elems) {
	if ($elemText =~ /(src|href)\=[\'\"](.*?)[\'\"]/i) {
	    my $relPath = $2;
	    my $absPath = &rel2abs_http($url, $relPath);
	    next if ($absPath == -1);
	    my $newText = $elemText;
	    $newText =~ s/\Q$relPath\E/$absPath/;
	    $newText =~ s/\&amp;/\&/g;
	    $html =~ s/\Q$elemText\E/$newText/;
	}
    }

    return $html;
}

# httpの絶対パスに変換
sub rel2abs_http {

    my ($url, $path) = @_;
    
    my $domain;
    if ($url =~ /^(http\:\/\/[^\/]+)/) {
	$domain = $1;
    } else {
	return -1;
    }
    my $pos;
    if ($url =~ /^(http\:\/\/.*\/)[^\/]*$/) {
	$pos = $1;
    }
    my $absPath;
    if ($path =~ /^http\:\/\//) {
	$absPath = $path;
    } elsif ($path =~ /^\/.*/) {
	$absPath = $domain . $path;
    } else {
        $absPath = $pos  . $path;
    }
    # /../../みたいなのがうまくいかなかったのでwhile
    while ($absPath =~ /(\/\.\/|\/\.\.\/)/) {
	$absPath =~ s/\/\.\///g;
	$absPath =~ s/\/[^\/]+\/\.\.\//\//g;
    }
    return $absPath; 
}


# charsetの有無によって文字コード判定とかcharsetを設定したりする。
# 判定できないようなときはutf-8にする
sub setCharset {

    my ($html) = @_;

    if ($html =~ /<meta.+?charset\=([a-zA-Z0-9\-_]+).+?>/i) {
	if (Encode::is_utf8($html)) {
	    my $tag = $&;
	    my $orig = $&;
	    $tag =~ s/$1/utf-8/;
	    $html =~ s/$orig/$tag/;
	    $charCode = 'utf8';
	} else {
	    $charCode = guess_encoding($html, qw/ascii euc-jp shiftjis utf8 7bit-jis/);
	}
    } else {
	if (Encode::is_utf8($html)) {
	    $charCode = 'utf8';
	    $html =~ s/<head>/<head>\n<meta charset=\"utf-8\">\n/i;
	} else {
	    my $charCode = guess_encoding($html, qw/ascii euc-jp shiftjis utf8 7bit-jis/);
	    if (ref($charCode)) {
		$charCode = $charCode->name;
	    }
	    $html =~ s/<head>/<head>\n<meta charset=\"$charCode\">\n/i;
	}
    }

    return $html;

}


1;
