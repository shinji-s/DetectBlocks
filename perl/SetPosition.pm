package SetPosition;

use strict;
use utf8;
use Digest::MD5 qw/md5_hex/;

use DetectBlocks;


our %opt = ('proxy'=>'http://proxy.kuins.net:8080/', 'nodec'=>1);


# 位置情報を書き込む
sub execAddPosition {

    my ($html, $execpath, $jspath) = @_;

    # 一時ファイル名
    my $cache = 'cache_' . substr(md5_hex($html), 0, 20) . '.html';
    my $returnhtml;

    # htmlの一時ファイル作成
    open(FILE, ">" . $cache);
    print FILE $html;
    close(FILE);

    # htmlに位置情報等を書き込む
    system "$execpath",'-j',"$jspath", "$cache", "$cache";

    # 位置情報が書き込まれたファイルを文字列にする
    open(FILE, "<" . $cache);
    while(<FILE>){$returnhtml .= $_;}
    close(FILE);

    unlink($cache);

    return $returnhtml;
}

# 基本的に外部からはこれを呼び出す
# ファイル、URL、文字列
sub setPosition {

    my ($target, $execpath, $jspath) = @_;

    my $html;
    # ローカルのファイルの場合
    if (-e $target) {
	open(FILE, "<" . $target);
	while(<FILE>){$html.=$_;}
	close(FILE);
    }
    # urlの場合
    elsif ($target =~ /^http:/) {
	my $DetectBlocks = new DetectBlocks();
	($html, $target) = $DetectBlocks->Get_Source_String($target, \%opt);
    }
    # その他はhtml文字列として扱う場合
    else {
	$html = $target;
    }

    return &SetPosition::execAddPosition($html, $execpath, $jspath);
}


1;
