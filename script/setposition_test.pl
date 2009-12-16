#!/usr/bin/env perl

use strict;
use utf8;

use SetPosition;


#my $str = "../sample/htmls/Kyoto/001.html";
my $str = "http://www.google.co.jp";


my $execpath = '../tools/addMyAttrToHtml/staticExe/wkhtmltopdf-reed';
my $jspath = '../tools/addMyAttrToHtml/staticExe/myExecJs.js';

print &SetPosition::setPosition($str, $execpath, $jspath);




