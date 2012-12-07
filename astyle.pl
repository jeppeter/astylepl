#! perl -w

use File::Find;
use File::Path  qw(make_path remove_tree);
use Config::IniFiles;
use IPC::Open2;
use POSIX;
use POSIX ":sys_wait_h";

my($st_Verbose);

sub ErrorExit($$)
{
    my($ec,$msg)=@_;
    my($pkg,$fn,$ln,$s)=caller(0);

    printf STDERR "[%-10s][%-20s][%-5d][ERROR]:%s\n",$fn,$s,$ln,$msg;
    exit($ec);
}

sub Warning($)
{
    my($msg)=@_;
    my($pkg,$fn,$ln,$s)=caller(0);

    printf STDERR "[%-10s][%-20s][%-5d][WARNING]:%s\n",$fn,$s,$ln,$msg;
}

sub DebugString($)
{
    my($msg)=@_;
    my($pkg,$fn,$ln,$s)=caller(0);

    if(defined($st_Verbose)&&$st_Verbose)
    {
        printf STDERR "[%-10s][%-20s][%-5d][INFO]:%s\n",$fn,$s,$ln,$msg;
    }
}

sub Usage
{
    my($ec)  = shift @_ ;
    my($msg) = $ec > 0 ? shift @_ : "";
    my($fp)=STDERR;

    if($ec == 0)
    {
        $fp = STDOUT;
    }
    else
    {
        print $fp "$msg\n";
    }

    print $fp "$0 [OPTIONS] dir ...\n";
    print $fp "\t-h|--help to display this help information\n";
    print $fp "\t-e|--regex  [regex] to specify the regular expression of file to check style\n";
    print $fp "\t-r|--real not make test ,just do real\n";
	print $fp "\t-c|--config [config file] to specify config file\n";
    print $fp "\t-s|--style [style string] to specify the astyle parameters\n";
    print $fp "\t-C|--cc [mailaddress] to specify the cc  address to send\n";
    print $fp "\t-b|--bcc [mailaddress] to specify the bcc address to send\n";
    print $fp "\t-f|--from [mailaddress] to specify the mail sender\n";
    print $fp "\t-xu|--user [account] to specify the mail sender account in the smtp server\n";
    print $fp "\t-xp|--passwd [password] to specify the password for the -xu\n";
    print $fp "\t-s|--server [server] to specify the server name it used in server:port format\n";
    print $fp "\t-v|--verbose to specify the verbose mode\n";

    exit($ec);
}

BEGIN
{
    my($hasastyle,$hassendemail);
    my ($sslversion);
    $hasastyle=`which astyle`;
    if("$hasastyle" eq "")
    {
        ErrorExit(3,"could not find astyle");
    }

    $hassendemail=`which sendemail`;
    if ("$hassendemail" eq "")
    {
    	ErrorExit(3,"could not find sendemail");
    }

}

my(@st_Regex,@st_MailAddress,$st_Astyle,$st_ConfigFile,$st_Test,@st_ScanDir);
my (@st_MailCC,@st_MailBCC,$st_MailFrom,$st_MailAccount,$st_MailPassword,$st_MailServer);

use constant ConfigCnst =>
{
    SectionName => 'AstyleSection',
    AstyleParam => 'AstyleParam',
    RealMode => 'RealMode',
    VerboseMode => 'VerboseMode',
    ScanDir => 'ScanDir',
    Filter => 'Filter',
    MailCC => 'MailCC',
    MailBCC => 'MailBCC',
    MailFrom => 'MailFrom',
    MailAccount => 'MailAccount',
    MailPassword => 'MailPassword',
    MailServer => 'MailServer',
};

sub CheckValidMailAddress($)
{
	my ($mail)=@_;

	if ( !($mail =~ m/\@/o))
	{
		ErrorExit(3,"$mail not valid mail address");		
	}
}

sub ParseConfig($)
{
    my($cf)=@_;
    my(%ini);
    my($v);
    tie %ini, 'Config::IniFiles', (-file => $cf);

	# now we should give the value
    if(defined($ini {ConfigCnst->{SectionName}}))
    {
        if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{AstyleParam}}))
        {
            $v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{AstyleParam}};
            if(!defined($st_Astyle))
            {
                if(ref($v) eq "")
                {
                    $st_Astyle = $v;
                }
                elsif(ref($v) eq "ARRAY")
                {
                    $st_Astyle = join(" ",@ {$v});
                }
            }
        }

        if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailAddress}}))
        {
            $v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailAddress}};
            if(ref($v) eq "")
            {
                my(@a);
                @a = split(";",$v);
                while(@a)
                {
                    push(@st_MailAddress,pop(@a));
                }
            }
            elsif(ref($v) eq "ARRAY")
            {
                while(@ {$v})
                {
                    push(@st_MailAddress,pop(@ {$v}));
                }
            }
        }

        if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{RealMode}}))
        {
            $v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{RealMode}};
            if(!defined($st_Test))
            {
                if(ref($v) eq "")
                {
                    $st_Test = $v ? 0 : 1;
                }
                elsif(ref($v) eq "ARRAY")
                {
					# get the last one
                    $st_Test = pop(@ {$v}) ? 0 : 1;
                }
            }
        }

        if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{VerboseMode}}))
        {
            $v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{VerboseMode}};
            if(ref($v) eq "")
            {
                $st_Verbose = $v;
            }
            elsif(ref($v) eq "ARRAY")
            {
				# get the last one
                $st_Verbose = pop(@ {$v});
            }
        }
        if(defined($ini{ConfigCnst->{SectionName}} {ConfigCnst->{ScanDir}}))
        {
        	$v = $ini{ConfigCnst->{SectionName}} {ConfigCnst->{ScanDir}};
            if(ref($v) eq "")
            {
                push (@st_ScanDir,$v);
            }
            elsif(ref($v) eq "ARRAY")
            {
				# get the last one
				while(@{$v})
				{
					push(@st_ScanDir,shift(@{$v}));
				}
            }        	
        }
        if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{Filter}}))
        {
        	my ($r);
        	$v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{Filter}};
			        	
            if(ref($v) eq "")
            {
            	$r = $v;
            	$r =~ s/\"//g;
            	$r =~ s/\'//g;
                push (@st_Regex,$r);
            }
            elsif(ref($v) eq "ARRAY")
            {
				# get the last one
				while(@{$v})
				{
					$r = pop(@{$v});
	            	$r =~ s/\"//g;
	            	$r =~ s/\'//g;
					push(@st_Regex,$r);
				}
            }        	
        }

		if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailCC}}))
		{
			$v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailCC}};
			if (ref ($v) eq "")
			{
				CheckValidMailAddress($v);
				push (@st_MailCC,$v);
			}
			elsif (ref($v) eq "ARRAY")
			{
				while(@{$v})
				{
					my ($cc)=shift(@{$v});
					CheckValidMailAddress($cc);
					push(@st_MailCC,$cc);
				}
			}
		}

		if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailBCC}}))
		{
			$v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailBCC}};
			if (ref ($v) eq "")
			{
				CheckValidMailAddress($v);
				push (@st_MailBCC,$v);
			}
			elsif (ref($v) eq "ARRAY")
			{
				while(@{$v})
				{
					my ($cc)=shift(@{$v});
					CheckValidMailAddress($cc);
					push(@st_MailBCC,$cc);
				}
			}			
		}

		if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailFrom}}))
		{
			$v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailFrom}};

			if (!defined($st_MailFrom))
			{
				if (ref ($v) eq "")
				{
					CheckValidMailAddress($v);
					$st_MailFrom=$v;
				}
				elsif (ref($v) eq "ARRAY")
				{
					my ($cc) = pop(@{$v});
					CheckValidMailAddress($cc);
					$st_MailFrom = $cc;
				}			
			}
		}
		if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailAccount}}))
		{
			$v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailAccount}};

			if (!defined($st_MailAccount))
			{
				if (ref ($v) eq "")
				{
					$st_MailAccount=$v;
				}
				elsif (ref($v) eq "ARRAY")
				{
					my ($cc) = pop(@{$v});
					$st_MailAccount = $cc;
				}
			}
		}
		if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailPassword}}))
		{
			$v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailPassword}};

			if (!defined($st_MailPassword))
			{
				if (ref ($v) eq "")
				{
					$st_MailPassword=$v;
				}
				elsif (ref($v) eq "ARRAY")
				{
					my ($cc) = pop(@{$v});
					$st_MailPassword = $cc;
				}
			}
		}

		if(defined($ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailServer}}))
		{
			$v = $ini {ConfigCnst->{SectionName}} {ConfigCnst->{MailServer}};

			if (!defined($st_MailServer))
			{
				if (ref ($v) eq "")
				{
					$st_MailServer=$v;
				}
				elsif (ref($v) eq "ARRAY")
				{
					my ($cc) = pop(@{$v});
					$st_MailServer = $cc;
				}
			}
		}
		
    }
    else
    {
        ErrorExit(4,"Config file $cf not valid");
    }

    return ;

}

sub ParseParam
{
    my($opt,$args);

    while(@ARGV)
    {
        $opt=$ARGV[0];
        if("$opt" eq "-h" || "$opt" eq "--help")
        {
            Usage(0);
        }
        elsif("$opt" eq "-e" || "$opt" eq "--regex")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need Regex");
            }
            $args=shift @ARGV;
            push(@st_Regex,$args);
        }
        elsif("$opt" eq "-s" || "$opt" eq "--style")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need Astyle params");
            }
            $args=shift @ARGV;
            $st_Astyle = $args;
        }
        elsif("$opt" eq "-m" || "$opt" eq "--mail")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need Mail Address");
            }
            $args=shift @ARGV;
            push(@st_MailAddress,$args);
        }
        elsif ("$opt" eq "-c" || "$opt" eq "--config")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need Config files");
            }
            $args=shift @ARGV;
            $st_ConfigFile = $args;
        }
        elsif ("$opt" eq "-C" || "$opt" eq "--cc")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need CC args");
            }
            $args=shift @ARGV;
            push(@st_MailCC,$args);
        }
        elsif ("$opt" eq "-b" || "$opt" eq "--bcc")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need BCC args");
            }
            $args=shift @ARGV;
            push(@st_MailBCC,$args);
        }
        elsif ("$opt" eq "-f" || "$opt" eq "--from")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need mail from");
            }
            $args=shift @ARGV;
            $st_MailFrom = $args;
        }
        elsif ("$opt" eq "-xu" || "$opt" eq "--user")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need mail user");
            }
            $args=shift @ARGV;
            $st_MailAccount = $args;
        }
        elsif ("$opt" eq "-xp" || "$opt" eq "--password")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need mail user");
            }
            $args=shift @ARGV;
            $st_MailPassword = $args;
        }
        elsif ("$opt" eq "-s" || "$opt" eq "--server")
        {
            shift @ARGV;
            if(@ARGV <= 0)
            {
                Usage(3,"Need mail user");
            }
            $args=shift @ARGV;
            $st_MailServer = $args;
        }
        elsif("$opt" eq "-r" || "$opt" eq "--real")
        {
            shift @ARGV;
            $st_Test = 0;
        }
        elsif("$opt" eq "-v" || "$opt" eq "--verbose")
        {
            shift @ARGV;
            $st_Verbose = 1;
        }
        else
        {
            last;
        }
    }
	if (!defined($st_ConfigFile))
    {
        @st_ScanDir = @ARGV;
    }
    else
    {
    	ParseConfig($st_ConfigFile);
    	# now to give the parse dir
    	if (@ARGV)
    	{
    		#remove all the directory ,use as command line
    		@st_ScanDir = ();
	    	while (@ARGV)
	    	{
	    		unshift(@st_ScanDir,pop(@ARGV));
	    	}
    	}
    }
    if(@st_ScanDir <= 0)
    {
       Usage(3,"Need at least one dir to scan");
    }

    if(@st_Regex <= 0)
    {
        Warning("Regex for file is null will scan all the files");
    }

    if(@st_MailAddress <= 0)
    {
        Warning("no mail address is specified");
    }

    if(!defined($st_Astyle))
    {
        Warning("astyle is not specified ,so we used --style=allman -U -z2");
        $st_Astyle="--style=allman -U -z2";
    }

    if(defined($st_Test) && $st_Test == 0)
    {
        Warning("will change the style");
    }
    elsif (!defined($st_Test))
    {
    	$st_Test = 1;
    }

    if (@st_MailCC <= 0 && @st_MailBCC <= 0)
    {
    	ErrorExit(3,"Should specify one mail to send");
    }

    if (!defined($st_MailFrom) ||
    	!defined($st_MailAccount) ||
    	!defined($st_MailPassword) ||
    	!defined($st_MailServer))
    {
    	ErrorExit(3,"mail from && mail account && mail password && mail server should specify");
    }
}


# now we should give the file

sub AstyleFileTest($$)
{
    my($file,$param)=@_;
    my($cmd);
    my($diffout,$fh);

    $cmd = "astyle ";
    $cmd .= $param;
    $cmd .= " < \"$file\" | diff \"$file\" - | ";

    DebugString("Run command $cmd");

    $diffout=0;
    open($fh,"$cmd") || die "could not run $cmd";

    while(<$fh>)
    {
        $diffout = 1;
    }
    close($fh);
    return $diffout;
}

sub AstyleFileReal($$)
{
    my($file,$param)=@_;
    my($cmd);
    my($ret);

    $cmd = "astyle ";
    $cmd .= $param;
    $cmd .= " \"$file\"";

    DebugString("Run command $cmd");

    $ret = system($cmd);
    if($ret == 0)
    {
# to remove the origine file when in the astyle command backup
        remove_tree("$file.orig");
    }
    return $ret;
}

my(@st_ScanFiles);

sub ScanFile
{
    my($curreg);
    my($curfile)=$_;
	
    if(-f $File::Find::name)
    {
        if(@st_Regex <= 0)
        {
            push(@st_ScanFiles,$File::Find::name);
        }
        else
        {
            foreach $curreg(@st_Regex)
            {
            	#DebugString("curfile $curfile reg $curreg");
                if($curfile =~ /$curreg/m)
                {
                	#DebugString("curfile $curfile");
                    push(@st_ScanFiles,$File::Find::name);
                }
            }
        }
    }
}

sub GetAllScanFiles
{
    my(@dirs)=@_;
    my($dir);

    foreach $dir(@dirs)
    {
        find(\&ScanFile,$dir);
    }

    return ;
}

sub RunAstyle($$)
{
    my($test,$param)=@_;
    my($cf,$ret);
    my(@testfiles);

    foreach $cf(@st_ScanFiles)
    {
        if($test)
        {
            $ret = AstyleFileTest($cf,$param);
            if($ret > 0)
            {
            	DebugString("get file $cf");
                push(@testfiles,$cf);
            }
        }
        else
        {
            AstyleFileReal($cf,$param);
        }
    }

    if($test)
    {
        return @testfiles;
    }

    return ();
}


sub SendMailBySendEmail($$)
{
	my ($subject,$con)=@_;
	my ($cmd,$u,$fh,$fo,$succ,$pid,$rpid);

	$cmd = " sendemail -f $st_MailFrom";
	$cmd .= " -xu $st_MailAccount ";
	$cmd .= " -xp $st_MailPassword ";
	$cmd .= " -u \"$subject\" ";
	$cmd .= " -s $st_MailServer ";	
	foreach $u (@st_MailCC)
	{
		$cmd .= " -cc $u ";
	}

	foreach $u (@st_MailBCC)
	{
		$cmd .= " -bcc $u ";
	}


	DebugString("Run Cmd $cmd");
	DebugString("Write mail\n$con");
	$pid=open2 ($fo,$fh,$cmd) ;
	if (!defined($pid))
	{
		die "could not run $cmd";
	}

	print $fh "$con";

	close($fh);

	$succ = 0;
	while(<$fo>)
	{
		my ($o)=$_;
		chomp($o);
		DebugString("o $o");
		if ($o =~ m/successfully/o)
		{
			$succ = 1;
		}
	}


	do
	{
		$rpid = waitpid($pid,WNOHANG);
		DebugString("rpid $rpid");
		if ($rpid != $pid)
		{
			sleep (1);
		}
	}while($rpid != $pid);
	close($fo);

	if ($succ == 0)
	{
		ErrorExit(4,"Run $cmd failed");
	}

	return 0;
}

sub MailAstyleTestRun()
{
    my(@testfiles);
    GetAllScanFiles(@st_ScanDir);
    if(!defined($st_Test))
    {
        $st_Test = 1;
    }
    @testfiles = RunAstyle($st_Test,$st_Astyle);
    if(@testfiles > 0)
    {
    	my ($con);
    	my ($subject);
    	my ($dir);
    	$con = "";
    	foreach $dir (@st_Scandir)
    	{
    		$con .= "Dir $dir\n";
    	}
        foreach(@testfiles)
        {
            $con .= "M $_\n";
        }
        $subject ="Subect : ";
        $dir = `date '+%Y-%m-%d-%H:%M:%S'`;
        chomp($dir);
        $subject .= $dir;
        $subject .= "Scan astyle not right";

        SendMailBySendEmail($subject,$con);        
    }
}

ParseParam();

DebugString( "Verbose $st_Verbose");
DebugString("regular expression @st_Regex");
DebugString("MailAddress @st_MailAddress");
DebugString("astyle param $st_Astyle");
DebugString("config file $st_ConfigFile");
DebugString("Test $st_Test");
DebugString("scan dir @st_ScanDir");
DebugString("mailcc @st_MailCC");
DebugString("mailbcc @st_MailBCC");
DebugString("mailfrom $st_MailFrom");
DebugString("mailaccount $st_MailAccount");
DebugString("mailpassword $st_MailPassword");
DebugString("mailserver $st_MailServer");
MailAstyleTestRun();


