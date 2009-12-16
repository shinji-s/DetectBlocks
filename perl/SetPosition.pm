package SetPosition;

use strict;
use utf8;
use Digest::MD5 qw/md5_hex/;
use POSIX;

use DetectBlocks;


our %opt = ('proxy'=>'http://proxy.kuins.net:8080/', 'nodec'=>1);

# 子プロセスが終了するまで待つ時間の最大値(秒)
our $loopLimit = 30;
# 子プロセスの状態を確認する間隔(秒)
our $interval = 0.5;


# 位置情報を書き込む
# エラーの場合は-1を返す
sub execAddPosition {

    my ($html, $execpath, $jspath) = @_;

    unless (-e $execpath && -e $jspath) {
	print "not exist execpath or jspath\n";
	return -1;
    }

    # 一時ファイル名
    my $cache = 'cache_' . substr(md5_hex($html), 0, 20) . '.html';
    my $returnhtml;

    # htmlの一時ファイル作成
    open(FILE, ">" . $cache);
    print FILE $html;
    close(FILE);

    # htmlに位置情報等を書き込む
#    system "$execpath",'-j',"$jspath", "$cache", "$cache";
    my $pid = fork();
    if ($pid > 0) {
        my $i = 0;
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
	open(FILE, "<" . $cache);
	while(<FILE>){$returnhtml .= $_;}
	close(FILE);
	unlink($cache);
    }
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
