package VBmodules::XcopyD;  # downloaded this module as FILE::Xcopy.pm from meta:cpan  (metacpan.org) Modified by VLB to add /D feature
my $module = "XcopyD.pm";

use 5.005_64;
use strict;
use vars qw($AUTOLOAD);
use Carp;
our(@ISA, @EXPORT, @EXPORT_OK, $ORIGINAL_VERSION, $VERSION, %EXPORT_TAGS);

# $g_dtg flags the use of the "xcopy /D:<timestamp>" feature via $g_dtgts
# $g_dtgts is the timestamp cutoff in seconds for new source files to be copied (used only if $g_dtg = 1)
# $g_nVB counts the number of files copied with unexpected return values
# $g_vbvCount is the number of remaining prints of files copied.
our ($g_dtg, $g_dtgts, $g_nVB, $g_vbvCount) = (0,0,0, 0);
$ORIGINAL_VERSION = '0.12';
$VERSION = '0.13'; # by VLB MemGemKeeper@gmail.com

# Global variables
our $VBCASE = "NONE";
our $VBpathname = "NONE"; # the current one being considered for update

# require Exporter;
# @ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(xcp xmv xcopy xmove find_files list_files output
    fmtTime format_number get_stat file_stat execute syscopy
);
%EXPORT_TAGS = ( 
  all => [@EXPORT_OK] 
);

use File::Find; 
use IO::File;
use File::Basename;


# use Fax::DataFax::Subs qw(:echo_msg disp_param);
sub xcopy;
sub xmove;
sub xcp;
sub xmv;
sub syscopy;
sub appendTextToFile;# vlb TBDNEW added 11/21/2018

=head1 NAME

File::XcopyD - copy files from a source (from_dir) to a destination (to_dir) 
      after comparing them to (1) a parameter timestamp or (2) the timestamp of the same file name already present in the destination folder

=head1 SYNOPSIS

    use File::XcopyD;
    my $fx = new File::XcopyD; 
    $fx->from_dir("/from/dir");
    $fx->to_dir("/to/dir");
    $fx->fn_pat('(\.pl|\.txt)$');  # files with pl & txt extensions
    $fx->param('s',1);             # search recursively to sub dirs
    $fx->param('verbose',1);       # Set to 1 for diagnostic print report
    $fx->param('DTG',1);           # Copy new files only if time stamp of source is newer or destination does not exist ($g_dtg)
    $fx->param('DTGTS',<timestamp>);         # Use this as the cutoff time stamp when DTG is set ($g_dtgts)
    $fx->param('VERBOSE_COUNT',<fileCount>);         # This as the cutoff count the display of files copied regardless of verbose ($g_vbvCount)
    $fx->param('log_file','logs/xcopyLogfile.txt'); # TBD1 log_file does not seem to work
    my ($sr, $rr) = $fx->get_stat; 
    $fx->xcopy;                    # or
    $fx->execute('copy'); 

    # the same with short name
    $fx->xcp("from_dir", "to_dir", "file_name_pattern");

=head1 DESCRIPTION

The File::XcopyD module provides two basic functions, C<xcopy> and
C<xmove>, which are useful for coping and/or moving a file or
files in a directory from one place to another. It mimics some of 
behaviours of C<xcopy> in DOS but with more functions and options. 


The differences between C<xcopy> and C<copy> are

=over 4

=item *

C<xcopy> searches files based on file name pattern if the 
pattern is specified.

=item *

C<xcopy> compares the timestamp and size of a file before it copies.

=item *

C<xcopy> takes different actions if you tell it to.

=back

=cut

{  # Encapsulated class data
    my %_attr_data =                        # default accessibility
    (
      _from_dir   =>['$','read/write',''],  # directory 1
      _to_dir     =>['$','read/write',''],  # directory 2 
      _fn_pat     =>['$','read/write',''],  # file name pattern
      _action     =>['$','read/write',''],  # action 
      _param      =>['%','read/write',{}],  # dynamic parameters
    );
    sub _accessible {
        my ($self, $attr, $mode) = @_;
        if (exists $_attr_data{$attr}) {
            return $_attr_data{$attr}[1] =~ /$mode/;
        } 
    }
    # classwide default value for a specified object attributes
    sub _default_for {
        my ($self, $attr) = @_;
        if (exists $_attr_data{$attr}) {
            return $_attr_data{$attr}[2];
        } 
    }
    # list of names of all specified object attributes

    sub _standard_keys {
        my $self = shift;
        # ($self->SUPER::_standard_keys, keys %_attr_data);
        (keys %_attr_data);
    }
    sub _accs_type {
        my ($self, $attr) = @_;
        if (exists $_attr_data{$attr}) {
            return $_attr_data{$attr}[0];
        } 
    }
}

=head2 The Constructor new(%arg)

Without any input, i.e., new(), the constructor generates an empty
object with default values for its parameters.

If any argument is provided, the constructor expects them in
the name and value pairs, i.e., in a hash array.

=cut

sub new {
    my $caller        = shift;
    my $caller_is_obj = ref($caller);
    my $class         = $caller_is_obj || $caller;
    my $self          = bless {}, $class;
    my %arg           = @_;   # convert rest of inputs into hash array
    # print join "|", $caller,  $caller_is_obj, $class, $self, "\n";
    foreach my $attrname ( $self->_standard_keys() ) {
        my ($argname) = ($attrname =~ /^_(.*)/);
        # print "attrname = $attrname: argname = $argname\n";
        if (exists $arg{$argname}) {
            $self->{$attrname} = $arg{$argname};
        } elsif ($caller_is_obj) {
            $self->{$attrname} = $caller->{$attrname};
        } else {
            $self->{$attrname} = $self->_default_for($attrname);
        }
        # print $attrname, " = ", $self->{$attrname}, "\n";
    }
    # $self->debug(5);
    return $self;
} # new


# implement other get_... and set_... method (create as neccessary)
sub AUTOLOAD {
    no strict "refs";
    my ($self, $v1, $v2) = @_;
    (my $sub = $AUTOLOAD) =~ s/.*:://;
    my $m = $sub;
    (my $attr = $sub) =~ s/(get_|set_)//;
        $attr = "_$attr";
    # print join "|", $self, $v1, $v2, $sub, $attr,"\n";
    my $type = $self->_accs_type($attr);
    croak "ERR: No such method: $AUTOLOAD.\n" if !$type;
    my  $v = "";
    my $msg = "WARN: no permission to change";
    if ($type eq '$') {           # scalar method
        $v  = "\n";
        $v .= "    my \$s = shift;\n";
        $v .= "    croak \"ERR: Too many args to $m.\" if \@_ > 1;\n";
        if ($self->_accessible($attr, 'write')) {
            $v .= "    \@_ ? (\$s->{$attr}=shift) : ";
            $v .= "return \$s->{$attr};\n";
        } else {
            $v .= "    \@_ ? (carp \"$msg $m.\n\") : ";
            $v .= "return \$s->{$attr};\n";
        }
    } elsif ($type eq '@') {      # array method
        $v  = "\n";
        $v .= "    my \$s = shift;\n";
        $v .= "    my \$a = \$s->{$attr}; # get array ref\n";
        $v .= "    if (\@_ && (ref(\$_[0]) eq 'ARRAY' ";
        $v .= "|| \$_[0] =~ /.*=ARRAY/)) {\n";
        $v .= "        \$s->{$attr} = shift; return;\n    }\n";
        $v .= "    my \$i;     # array index\n";
        $v .= "    \@_ ? (\$i=shift) : return \$a;\n";
        $v .= "    croak \"ERR: Too many args to $m.\" if \@_ > 1;\n";
        if ($self->_accessible($attr, 'write')) {
            $v .= "    \@_ ? (\${\$a}[\$i]=shift) : ";
            $v .= "return \${\$a}[\$i];\n";
        } else {
            $v .= "    \@_ ? (carp \"$msg $m.\n\") : ";
            $v .= "return \${\$a}[\$i];\n";
        }
    } else {                      # assume hash method: type = '%'
        $v  = "\n";
        $v .= "    my \$s = shift;\n";
        $v .= "    my \$a = \$s->{$attr}; # get hash array ref\n";
        $v .= "    if (\@_ && (ref(\$_[0]) eq 'HASH' ";
        $v .= " || \$_[0] =~ /.*=HASH/)) {\n";
        $v .= "        \$s->{$attr} = shift; return;\n    }\n";
        $v .= "    my \$k;     # hash array key\n";
        $v .= "    \@_ ? (\$k=shift) : return \$a;\n";
        $v .= "    croak \"ERR: Too many args to $m.\" if \@_ > 1;\n";
        if ($self->_accessible($attr, 'write')) {
            $v .= "    \@_ ? (\${\$a}{\$k}=shift) : ";
            $v .= "return \${\$a}{\$k};\n";
        } else {
            $v .= "    \@_ ? (carp \"$msg $m.\n\") : ";
            $v .= "return \${\$a}{\$k};\n";
        }
    }
    # $self->echoMSG("sub $m {$v}\n",100);
    *{$sub} = eval "sub {$v}";
    goto &$sub;
}

sub DESTROY {
    my ($self) = @_;
    # clean up base classes
    return if !@ISA;
    foreach my $parent (@ISA) {
        next if $self::DESTROY{$parent}++;
        my $destructor = $parent->can("DESTROY");
        $self->$destructor() if $destructor;
    }
}
#######################################################################

=head3 xcopy($from, $to, $pat, $par)

Input variables:

  $from - a source file or directory 
  $to   - a target directory or file name 
  $pat - file name match pattern, default to {.+}
  $par - parameter array
    log_file - log file name with full path
    

Variables used or routines called: 

  get_stat - get file stats
  output   - output the stats
  execute  - execute a action

How to use:

  use File::XcopyD;
  my $obj = File::XcopyD->new;
  # copy all the files with .txt extension if they exists in /tgt/dir
  $obj->xcopy('/src/files', '/tgt/dir', '\.txt$'); 

  use File:XcopyD qw(xcopy); 
  xcopy('/src/files', '/tgt/dir', '\.txt$'); 

Return: ($n, $m). 

  $n - number of files copied or moved. 
  $m - total number of files matched

=cut

sub xcopy {
    my $self = shift;
    my $class = ref($self)||$self;
    my($from,$to, $pat, $par) = @_;
    $self->action('copy');
    my ($sr, $rr) = $self->get_stat(@_); 
    return $self->execute; 
}
###########################################################################
=head3 syscopy($from, $to)

Input variables:

  $from - a source file or directory 
  $to   - a target directory or file name 

Variables used or routines called: 


How to use syscopy :

  use File::XcopyD;
  syscopy('/src/file_a', '/tgt/dir/file_b');  # copy to a file
  syscopy('/src/file_a', '/tgt/dir');         # copy to a dir
  syscopy('/src/dir_a', '/tgt/dir_b');        # copy a dir to a dir

Return: none ?? It returns a derivative of the return from the system call.

=cut

sub syscopy 
{
    my $self = shift;
    my $class = ref($self)||$self;
    my ($from, $to) = @_;
    
    my @arg = ();
    $arg[0] = '/bin/cp';
    if ($^O eq 'VMS') 	{return &rmscopy(@_);}
    elsif ($^O eq 'MacOS') {return &maccopy(@_);}
    elsif ($^O eq 'MSWin32')
    {
        $arg[0] = 'copy';
        $from =~ s{/}{\\}g;
        $to   =~ s{/}{\\}g;
        push @arg, "\"$from\"", "\"$to\"";
    }
    else {push @arg, '-p', '-f', $from, $to; } 

    #print " ARG: @arg\n";
    my $command = "@arg > logs/null.txt"; # Place output in null.txt since stdout may not be present. TBDNEW 11/20/2018

    #print " command is $command\n";
    my $rcode = system($command);
    # MSWin32 returns 256: $rcode>>8 = 1
    # Unix returns 0: 
    my $r = "";
    #print "return code of $command is $rcode\n";
    if ($^O eq 'MSWin32') {
        $r = $rcode>>8;
	#print "Win32 return code of $command is :$rcode:  :$r:\n";
    } else {
        $r = ($rcode==0)?1:0;
    }
    return $r;
} # syscopy 
###########################################################################
# Functions by vlb  MemGemKeeper@gmail.com
###########################################################################
=head3 appendTextToFile($text, $to)
This function is used to add text to a file (useful for logging)

Input variables:

  $to   - <file path> a target file name 
  $text - <text> a string to append to a file named $to (This can be a file name itself)
  $option - <text_file_option>  0: text string; 1: file name to copy content to $to

Variables used or routines called: 

How to use appendTextToFile :

  use File::XcopyD;
  appendTextToFile('<file path>','<text>', <text_file_option>);  # copy text to a file

Return:
 1 if the append is made with this call; 
 0 if append fails because output file cannot be opened for append, 
-2 if source file to be appeneded cannot be opened

=cut

sub appendTextToFile  # TBDNEW VLB 11/21/2018
{
	# P0: The file name to modify
	# P1: content to append to the file (Be sure a newline is included if it is desired)
	# P2: Form code for content above:  (0: Text string; 1: Text file name)
    	my ($to, $text, $option) = @_;

	my $appendFile = ">>" . $to;
	unless (open (OUTFILAP, $appendFile )) 
	{
		print "Cannot open :: $to  ::  for append of $text with option $option\n";
		return 0;
	}
	if ($text) # content present
	{
		
		if ($option) 
		{# content is a text file name
			#print "XcopyD :: $text :: is a file name to append \n\n";
			#&sysLogitX ("Appending content of file $_[1] to $to ");VBmodules::SjniSectionB::okSJNI("test2");
			if (!open (INFIL, $_[1] ))  {return -2;}
			while (<INFIL>)
			{
				print OUTFILAP $_;
				#print "XcopyD appending line: $_\n";
			}
			close INFIL;
			#print "XcopyD  Appended content of file $_[1] to $to\n"; # VBmodules::SjniSectionB::okSJNI("test3");
	
		}
		else 
		{
			#print "XcopyD :: $text ::  is a string to append\n\n";
			print OUTFILAP $text;
		} # content is string
	}
	close OUTFILAP;
	#&sysLogitX ("Appended content of file $_[1] to $to");
	return 1;

} # appendTextToFile  
######################################################################

sub maccopy {
    require Mac::MoreFiles;
    my($from, $to) = @_;
    my($dir, $toname);
    return 0 unless -e $from;
    if ($to =~ /(.*:)([^:]+):?$/) {
        ($dir, $toname) = ($1, $2);
    } else {
        ($dir, $toname) = (":", $to);
    }
    unlink($to);
    return Mac::MoreFiles::FSpFileCopy($from, $dir, $toname, 1);
}
#################################################################

=head3 xmove($from, $to, $pat, $par)

Input variables:

  $from - a source file or directory 
  $to   - a target directory or file name 
  $pat - file name match pattern, default to {.+}
  $par - parameter array
    log_file - log file name with full path
    

Variables used or routines called: 

  get_stat - get file stats
  output   - output the stats
  execute  - execute a action

How to use:

  use File::XcopyD;
  my $obj = File::XcopyD->new;
  # move the files with .txt extension if they exists in /tgt/dir
  $obj->xmove('/src/files', '/tgt/dir', '\.txt$'); 

Return: ($n, $m). 

  $n - number of files copied or moved. 
  $m - total number of files matched

=cut

sub xmove {
    my $self = shift;
    my $class = ref($self)||$self;
    my($from,$to, $pat, $par) = @_;
    $self->action('move');
    my ($sr, $rr) = $self->get_stat(@_); 
    return $self->execute; 
};

#################################################################

*xcp = \&xcopy;
*xmv = \&xmove;
#################################################################
=head3 execute ($act)

Input variables:

  $act  - action: 
       report|test - test run
       copy|CP - copy files from source to target only if
                 1) the files do not exist or 
                 2) newer than the existing ones
                 This is default.
  overwrite|OW - copy files from source to target only if
                 1) the files exist and 
                 2) no matter is older or newer 
       move|MV - same as in copy except it removes from source the  
                 following files: 
                 1) files are exactly the same (size and time stamp)
                 2) files are copied successfully
     update|UD - copy files only if
                 1) the file exists in the target and
                 2) newer in time stamp 

Variables used or routines called: None

How to use execute:

  use File::XcopyD;
  my $obj = File::XcopyD->new;
  # update all the files with .txt extension if they exists in /tgt/dir
  $obj->get_stat('/src/files', '/tgt/dir', '\.txt$'); 
  my ($n, $m) = $obj->execute('overwrite'); 

Return: ($n, $m). 

  $n - number of files copied or moved. 
  $m - total number of files matched
Global output:
  $g_nVB - number of files copied or moved with a return code not anticipated by author.

=cut

sub execute 
{ # execute()
    my $self = shift;
    my ($act) = @_; 
    $act = $self->action  if ! $act;
    $act = 'test'         if ! $act; 
    my $sr = $self->param('stat_ar');
    my $rr = $self->param('file_ar');
    croak "ERR: please run get_stat first.\n" if ! $rr; 
    $self->action($act);
    my $par = $self->param; 
    my $vbm = ${$par}{verbose};
    my $dtg = ${$par}{DTG}; 
    my $dtgts = ${$par}{DTGTS}; 
    my $g_dtg = ${$par}{DTG}; 
    my $g_dtgts = ${$par}{DTGTS}; 
    $g_vbvCount = ${$par}{VERBOSE_COUNT}; 
    # print "execute g_vbvCount=$g_vbvCount\r\n";

    my $fdir = $self->from_dir;
    my $tdir = $self->to_dir;
    my ($n, $m, $tp, $f1, $f2) = (0,0,"","","");
    my $tm_bit = 1;
	#print "exe: NO Verbose \r\n" if !$vbm;
	#print "exe: Verbose = $vbm \r\n" if $vbm;
	#print "exe: timestamp cutoff =$dtg \r\n" if $dtg && $vbm;
	#print "exe: There is NO timestamp cutoff  \r\n" if !$dtg && $vbm;
    
    foreach my $f (sort keys %{$rr}) 
    { # foreach loop on files that might be copied
        ++$m; 
        $tp = ${$rr}{$f}{type};   # Extract the type of the copy operation
        # skip if the file only exists in to_dir

        next if ($tp =~ /^OLD/); 
        next if ($tp =~ /^SRCREJ/); # TBDNEW 11/21/2018 Do not copy if the NEW file is not new enough to meet the date cutoff

	#if (($VBCASE eq "SRCREJ")  && ($tp eq "NEW")) {print " tp is $tp with $VBCASE\n";}mysterious

        my $f3 = $f; $f3 =~ s{^\.\/}{};
        $f1 = join '/', $fdir, $f3; 
        $f2 = join '/', $tdir, $f3; 
        next if -d $f1;       # skip the sub-dirs
        if (! -f $f1) {
           carp "WARN: 1 - could not find $f1\n";
           next;
        }
        my $td2 = dirname($f2); # VLB
	$VBpathname = $td2; # VBTBDNEW
	
        if (!-d $td2) 
	{# Need to make new path  VBTBDMOD
            # we need to get original mask and imply here VBTBDNEW
            my $testmake = mkdir $td2; # VLB TBDNEWMOD
	    #VLB VBTBDNEW1 9/9/2018 Solved folder mkdir order issue.
	    if ($testmake == 0) 
	    {# Failed to make new path $td2 initially must make it sequentially
		#print "\nFailed to make $td2 initially.Will build it now \n\n";
		# Make the directories from the beginning until $td2 works.
		my @vbdirParts = split (/\//,$td2);
		my $vbTotpath = "";
    		foreach my $vbpart (@vbdirParts)
		{# loop on directory parts
			$vbTotpath .= ($vbpart . "/"); 
			if (!-d $vbTotpath) 
			{# directory segment does not yet exist
				if (!mkdir $vbTotpath)
				{
					print "ERROR in making $vbTotpath\n";
					die ("XcopyD.pm ERROR in making $vbTotpath");
				}
			}# directory segment does not yet exist
			
		} # loop on directory parts

	    } # Failed to make full path initially
        }# Need to make new path
# VLB VBTBDNEW2  9/9/2018
 	#print "dest file is $act  \n" if $vbm;
        if ($act =~ /^c/i)
	{            # copy
            if ($tp =~ /^(NEW|EX1|EX2)/) 
	    { 

		my $textInsert = "";

		#print "dest file to be populated by copy is $f2 \n" if $vbm;
 		
                if ($self->syscopy($f1, $f2)) 
		{ # Normal for Mac OS X
                	++$n;
			print "$n:$tp: Mac/OSX copying to dest  $f1\n" if $vbm; 
			$textInsert = "$g_vbvCount::$n::$tp: Mac OSX copying to dest  $f1\n";
                }
		else
		{ # Normal for windows
			++$g_nVB;
			print "$n:$tp: Windows copying to dest  $f1\n" if $vbm; 
			$textInsert = "$g_vbvCount :: $n :: $tp: Windows copying to dest  $f1\n";
                 	# carp "ERR: could not copy $f1: $!\n";  # why is this an error when it works for Windows? TBD1 8/24/2018
			#print "Above carp appears to be spurious.\n";  # TBDNEW 8/24/2018
                }

		&appendTextToFile('XcopyDlog.txt',$textInsert, 0) if $g_vbvCount;

		if ($g_vbvCount > 0)
		{# test for last listing
			$g_vbvCount--;
			if ($g_vbvCount == 0)
			{# Above is last listing to show
				$textInsert = "The files copied will no longer be listed in XcopyDlog.txt.\n";
				&appendTextToFile('XcopyDlog.txt',$textInsert, 0);
			}# Above is last listing to show
		}# test for last listing

            } else 
	    {
            # (too verbose) print "copying $f1 to $f2: skipped.\n" if $vbm;  # VBTBDEL
            }
        } elsif ($act =~ /^m/i) 
	{       # move
            if ($tp =~ /^(NEW|EX1|EX2)/) { 
                if ($self->syscopy($f1, $f2)) {
                    ++$n; 
                    unlink $f1; 
                    print "$f1 moved to $f2\n" if $vbm; 
                } else {
                  carp "ERR: could not move $f1: $!\n"; 
                }
            } else 
		{ 
                print "moving $f1 to $f2: skipped.\n" if $vbm; 
            }
        } 
	elsif ($act =~ /^u/i)
	{       # update
            if ($tp =~ /^(EX1|EX2)/) 
	    { 
                if ($self->syscopy($f1, $f2))
		{
	    	    print "UPDATE dest file is $f2 \n" if $vbm;
                    ++$n; 
                    print "$f1 updated to $f2\n" if $vbm; 
                } else
		{
                  carp "ERR: could not update $f2: $!\n"; 
                }
            } 
	    else 
	    {
                print "updating $f1 to $f2: skipped.\n" if $vbm; 
            }
        } 
	elsif ($act =~ /^o/i)
        {       # overwrite
            if ($tp =~ /^(EX0|EX1|EX2)/)
	    { 
                if ($self->syscopy($f1, $f2))
		{
                    ++$n; 
                    print "$f1 overwritten $f2\n" if $vbm; 
                }
		else 
		{
                  carp "ERR: could not overwrite $f2: $!\n"; 
                }
            }
	    else 
	    {
                print "overwriting $f1 to $f2: skipped.\n" if $vbm; 
            }
        }
 	else 
	{
            carp "WARN: $f - do not know what to do.\n";
        } 
    } # foreach loop on files that might be copied
    $self->output($sr,$rr,"",$par); 
    print "Execute returning : $n : $m:\n" if $vbm;
    return ($n ,$m);
} # execute()

#################################################################
=head3 get_stat($from, $to, $pat, $par)

Input variables for get_stat():

  $from - a source file or directory 
  $to   - a target directory or file name 
  $pat - file name match pattern, default to {.+}
  $par - parameter array
    log_file - log file name with full path
    

VLB expanded the  /D option from implicit (/D alone) to DTG=[(0=implicit/D alone), (1=DTGTS used) and using DTGTS parameters]
I currently only implemented /S parameter. Here is an example on how to
use the module:

  package main;
  my $self = bless {}, "main";

  use File::XcopyD;
  use Debug::EchoMessage;

  my $xcp = File::XcopyD->new;
  my $fm  = '/opt/from/dir';
  my $to  = '/opt/to/dir';
  my %p = (s=>1);   # or $xcp->param('s',1);
  my ($a, $b) = $xcp->get_stat($fm, $to, '\.sql$', \%p);
  # $self->disp_param($a);
  # $self->disp_param($b);
  $xcp->output($a,$b);

  $xcp->param('verbose',1);
  $xcp->param('DTG',1);
  $xcp->param('DTGTS',$<dtgts>);
  my ($n, $m) = $xcp->execute('cp');
  # $self->disp_param($xcp->param());

  print "Total number of files matched: $m\n";
  print "Number of files copied with a return code expected by original creator: $n\n"; 
  print "Number of files copied with a 0 return code : $g_nVB\n"; 

I will implement the following parameters gradually:

  source       Specifies the file(s) to copy.
  destination  Specifies the location and/or name of new files.
  /A           Copies only files with the archive attribute set,
               doesn't change the attribute.
  /M           Copies only files with the archive attribute set,
               turns off the archive attribute.
  /D:m-d-y     Copies files changed on or after the specified date. [This was implemented on 11/20/2018 by VLB with parameters $DTG and $DTGTD]
               If no date is given, copies only those files whose   
               source time is newer than the destination time.	    [This had been originally implemented by default]
  /EXCLUDE:file1[+file2][+file3]...
               Specifies a list of files containing strings.  
               When any of the strings match any part of the absolute 
               path of the file to be copied, that file will be 
               excluded from being copied.  For example, specifying a 
               string like \obj\ or .obj will exclude all files 
               underneath the directory obj or all files with the
               .obj extension respectively.
  /P           Prompts you before creating each destination file.
  /S           Copies directories and subdirectories except empty ones.
  /E           Copies directories and subdirectories, including empty 
               ones.  Same as /S /E. May be used to modify /T.
  /V           Verifies each new file.
  /W           Prompts you to press a key before copying.
  /C           Continues copying even if errors occur.
  /I           If destination does not exist and copying more than one 
               file,
               assumes that destination must be a directory.
  /Q           Does not display file names while copying.
  /F           Displays full source and destination file names while 
               copying.
  /L           Displays files that would be copied.
  /H           Copies hidden and system files also.
  /R           Overwrites read-only files.
  /T           Creates directory structure, but does not copy files. 
               Does not include empty directories or subdirectories. 
               /T /E includes empty directories and subdirectories.
  /U           Copies only files that already exist in destination.
  /K           Copies attributes. Normal XcopyD will reset read-only 
               attributes.
  /N           Copies using the generated short names.
  /O           Copies file ownership and ACL information.
  /X           Copies file audit settings (implies /O).
  /Y           Suppresses prompting to confirm you want to overwrite an
               existing destination file.
  /-Y          Causes prompting to confirm you want to overwrite an
               existing destination file.
  /Z           Copies networked files in restartable mode.

Variables used or routines called: 

  from_dir   - get from_dir
  to_dir     - get to_dir
  fn_pat     - get file name pattern
  param      - get parameters
  find_files - get a list of files from a dir and its sub dirs
  list_files - get a list of files from a dir
  file_stat  - get file stats
  fmtTime    - format time


How to use:

  use File::XcopyD;
  my $obj = File::XcopyD->new;
  # get stat for all the files with .txt extension 
  # if they exists in /tgt/dir
  $obj->get_stat('/src/files', '/tgt/dir', '\.txt$'); 

  use File:XcopyD qw(xcopy); 
  xcopy('/src/files', '/tgt/dir', 'OW', '\.txt$'); 

Return: ($sr, $rr). 

  $sr - statistic hash array ref with the following keys: 
      OK    - the files are the same in size and time stamp
        txt - "The Same size and time"
        cnt - count of files
        szt - total bytes of all files in the category
      NO    - the files are different either in size or time
        txt - "Different size or time"
        cnt - count of files
        szt - total bytes of all files in the category
      OLD{txt|cnt|szt} - "File does not exist in FROM folder"
      NEW{txt|cnt|szt} - "File does not exist in TO folder"
      EX0{txt|cnt|szt} - "File is older or the same"
      EX1{txt|cnt|szt} - "File is newer and its size bigger"
      EX2{txt|cnt|szt} - "File is newer and its size smaller"
      STAT
        max_size - largest  file in all the selected files
        min_size - smallest file in all the selected files.
        max_time - time stamp of the most recent file
        min_time - time stamp of the oldest file 

The sum of {OK} and {NO} is equal to the sum of {EX0}, {EX1} and
{EX2}. 

  $rr - result hash array ref with the following keys {$f}{$itm}:
      {$f} - file name relative to from_dir or to_dir
         file - file name without dir parts
         pdir - parent directory
         prop - file stat array
         rdir - relative file name to the $dir
         path - full path of the file
         type - file status: NEW, OLD, EX1, or EX2
         f_pdir - parent dir for from_dir
         f_size - file size in bytes from from_dir
         f_time - file time stamp    from from_dir
         t_pdir - parent dir for to_dir
         t_size - file size in bytes from to_dir 
         t_time - file time stamp    from to_dir 
         tmdiff - time difference in seconds between the file 
                  in from_dir and to_dir
         szdiff - size difference in bytes between the file 
                  in from_dir and to_dir
         action - suggested action: CP, OW, SK

The method also sets the two parameters: stat_ar, file_ar and you can 
get it using this method: 

    my $sr = $self->param('stat_ar');
    my $rr = $self->param('file_ar');

=cut

sub get_stat {
    my $self = shift;
    my $class = ref($self)||$self;
    my($from,$to, $pat, $par) = @_;
    $from = $self->from_dir if ! $from; 
    $to   = $self->to_dir   if ! $to; 
    $pat  = $self->fn_pat   if ! $pat; 
    $par  = $self->param    if ! $par; 
    croak "ERR: source dir or file not specified.\n" if ! $from; 
    croak "ERR: target dir not specified.\n"         if ! $to; 
    croak "ERR: could not find src dir - $from.\n"   if ! -d $from;
    # croak "ERR: could not find tgt dir - $to.\n"     if ! -d $to  ; For this version (XcopyD), dest folder need not exist.
    $self->from_dir($from);
    $self->to_dir($to);
    $self->fn_pat($pat);
    my ($re, $n, $m, $t);
    if ($pat) { $re = qr {$pat}i; } else { $re = qr {.+}; } # VBTBDMOD Added 'i' so pattern case will be ignored
    # $$re = qr {^lib_df51t5.*(\.pl|\.txt)$};
    my $far = bless [], $class;      # from array ref 
    my $tar = bless [], $class;      # to   array ref
    # get file name list
    if ($par && exists ${$par}{s}) {  # search sub-dir as well 
        $far = $self->find_files($from, $re); 
        $tar = $self->find_files($to,   $re); 
    } else {                          # only files in $from
        $far = $self->list_files($from, $re);
        $tar = $self->list_files($to,   $re); 
    }
    # convert array into hash 
    my $fhr = $self->file_stat($from, $far);
    my $thr = $self->file_stat($to,   $tar); 
    my %r = ();
    my %s = ( OK=>{txt=>"The Same size and time"},
              NO=>{txt=>"Different size or time"},
              OLD=>{txt=>"File does not exist in FROM folder"},
              NEW=>{txt=>"File does not exist in TO folder"},
              EX0=>{txt=>"File is older or the same"},
              EX1=>{txt=>"File is newer and its size bigger"},
              EX2=>{txt=>"File is newer and its size smaller"},
              STAT=>{max_size=>0, min_size=>99999999999, 
                     max_time=>0, min_time=>99999999999},
    );

    my $vbm = ${$par}{verbose};
    my $g_dtg = ${$par}{DTG}; 
    my $g_dtgts = ${$par}{DTGTS};
    #$g_vbvCount = ${$par}{VERBOSE_COUNT}; 
    #print "get_stat g_vbvCount=$g_vbvCount\r\n";

    foreach my $f (keys %{$fhr}) {
        $s{STAT}{max_size} = ($s{STAT}{max_size}<${$fhr}{$f}{size}) ?
            ${$fhr}{$f}{size} : $s{STAT}{max_size}; 
        $s{STAT}{min_size} = ($s{STAT}{min_size}>${$fhr}{$f}{size}) ?
            ${$fhr}{$f}{size} : $s{STAT}{min_size}; 
        $s{STAT}{max_time} = ($s{STAT}{max_time}<${$fhr}{$f}{time}) ?
            ${$fhr}{$f}{time} : $s{STAT}{max_time}; 
        $s{STAT}{min_time} = ($s{STAT}{min_time}>${$fhr}{$f}{time}) ?
            ${$fhr}{$f}{time} : $s{STAT}{min_time}; 
        $r{$f} = {file=>${$fhr}{$f}{file},  f_pdir=>${$fhr}{$f}{pdir}, 
            f_size=>${$fhr}{$f}{size},
            f_time=>$self->fmtTime(${$fhr}{$f}{time})}; 
        if (! exists ${$thr}{$f}) 
	{ # file does not exist in the TO folder. Do we want to copy it?
	    my $sourcetime = ${$fhr}{$f}{time};
	    #print "Comparing source time=$sourcetime with cutoff time=$g_dtgts with g_dtg=$g_dtg\n";
 	    if (!$g_dtg || ($sourcetime > $g_dtgts))
	    { # Either not using time stamp or time stamp is less than the source time. Must copy
            	$s{NEW}{szt} += ${$fhr}{$f}{size}; 
            	$r{$f}{t_pdir}=$to;
	    	$r{$f}{t_size}="";      
            	$r{$f}{t_time}=""; $r{$f}{tmdiff}="";
            	$r{$f}{szdiff}="";
		$r{$f}{action}="CP";
            	$VBCASE = "NEW";
		print "Copy this NEW file\n" if $vbm;
           	$r{$f}{type}  = 'NEW';
            	++$s{NEW}{cnt};
	    }
	    else # TBDNEW 11/21/2018
	    {
  		$r{$f}{action}="no action";
		print "Skip copy of this NEW file since its date is not newer than cutoff\n" if $vbm;

            	$r{$f}{type}  = 'SRCREJ';#  New case. A new file but it is not newer than the cutoff to copy
            	$VBCASE = "SRCREJ";#  New case. A new file but it is not newer than the cutoff to copy
  	    } 
           
            next;
        }# NEW or SRCREJ

        $r{$f}{t_pdir}=${$thr}{$f}{pdir}; 
        $r{$f}{t_size}=${$thr}{$f}{size}; 
        $r{$f}{t_time}=$self->fmtTime(${$thr}{$f}{time});
        $r{$f}{tmdiff}=${$thr}{$f}{time}-${$fhr}{$f}{time};
        $r{$f}{szdiff}=${$thr}{$f}{size}-${$fhr}{$f}{size};
        if (${$fhr}{$f}{size} == ${$thr}{$f}{size} && 
            ${$fhr}{$f}{time} == ${$thr}{$f}{time} )
        {# no point in copying if the files are identical in size, name, and timestamp
            ++$s{OK}{cnt};
            $s{OK}{szt} += ${$fhr}{$f}{size}; 
            $r{$f}{action}="no action";
            $r{$f}{type}  = 'OK'; 
            next;
        }
        $s{NO}{szt}  += ${$fhr}{$f}{size}; 
        $r{$f}{type}  = 'NO'; 
        ++$s{NO}{cnt}; 
	#
	my $destTime = ${$thr}{$f}{time} + 1; # Must add 1 since the same file can have a timestamp off by 1 second
	
	# OS X appears to XCOPY a new file putting time stamp 1 second before the source file time stamp.
	# THis causes the file to be updated again with the next XcopyD so I added 1 second to the destination date below to compensate for this ideosyncrasy
        if (${$fhr}{$f}{time} > $destTime) # VBTBDNEW 8/2018 Added 1 second to end spurious updates. (A CLUGE for OS X file dates)
        {# newer and bigger1
		#my $VBdelt = ${$fhr}{$f}{time} - (${$thr}{$f}{time});# VBTBDNEW  
        	#if ($VBdelt > 1) {print "Delta time is $VBdelt seconds for \n$VBpathname \n";}  # VBTBDNEW
	    #Ask same question AGAIN!!:
	        print "Dest time is bigger/older=${$thr}{$f}{time} then source timestamp= ${$fhr}{$f}{time}\r\n" if !$g_dtg;
            if (${$fhr}{$f}{time} > $destTime) # VBTBDNEW 8/2018: Added 1 to end spurious updates 
            { # newer and bigger2
		print "EXT1: Source time is newer/larger  ${$fhr}{$f}{time}\r\n" if $vbm;
		print "EXT1: Dest time is older/smaller   ${$thr}{$f}{time}\r\n" if $vbm;

                ++$s{EX1}{cnt};
                $VBCASE = "EX1";
                $s{EX1}{szt} += ${$fhr}{$f}{size}; 
                $r{$f}{type}  = 'EX1';
                
            } # newer and bigger2
            else
            { # NOT newer and bigger2
		#print "EXT2: Source time is NOT newer/larger  ${$fhr}{$f}{time}\r\n" if $vbm;
		#print "EXT2: Dest time is NOT older/smaller   ${$thr}{$f}{time}\r\n" if $vbm;

                ++$s{EX2}{cnt};
                $s{EX2}{szt} += ${$fhr}{$f}{size}; 
                $r{$f}{type}  = 'EX2';
                
                $VBCASE = "EX2";
            } # NOT newer and bigger2
            $r{$f}{action}="OW";
        }# newer and bigger
        else
        {# not newer and bigger
            $r{$f}{action}="SK";
            ++$s{EX0}{cnt};
            $s{EX0}{szt} += ${$fhr}{$f}{size}; 
            $r{$f}{type}  = 'EX0'; 
        } # NOT newer and bigger
    } # loop on keys
    
    foreach my $f (keys %{$thr}) {
        $s{STAT}{max_size} = ($s{STAT}{max_size}<${$thr}{$f}{size}) ?
            ${$thr}{$f}{size} : $s{STAT}{max_size}; 
        $s{STAT}{min_size} = ($s{STAT}{min_size}>${$thr}{$f}{size}) ?
            ${$thr}{$f}{size} : $s{STAT}{min_size}; 
        $s{STAT}{max_time} = ($s{STAT}{max_time}<${$thr}{$f}{time}) ?
            ${$thr}{$f}{time} : $s{STAT}{max_time}; 
        $s{STAT}{min_time} = ($s{STAT}{min_time}>${$thr}{$f}{time}) ?
            ${$thr}{$f}{time} : $s{STAT}{min_time}; 
        next if (exists ${$fhr}{$f}); 
        ++$s{OLD}{cnt};
        $s{OLD}{szt} += ${$thr}{$f}{size}; 
        $r{$f} = {file=>${$thr}{$f}{file}, 
            f_pdir=>"", f_size=>"", f_time=>"", 
            t_pdir=>${$thr}{$f}{pdir},
            t_size=>${$thr}{$f}{size},
            t_time=>$self->fmtTime(${$thr}{$f}{time}),
            tmdiff=>"", szdiff=>"", 
            action=>"NA", type  =>'OLD' 
        };
    }
    $s{STAT}{tmdiff}=$s{STAT}{max_time}-$s{STAT}{min_time};
    $s{STAT}{szdiff}=$s{STAT}{max_size}-$s{STAT}{min_size};
    $s{STAT}{max_time}=$self->fmtTime($s{STAT}{max_time});
    $s{STAT}{min_time}=$self->fmtTime($s{STAT}{min_time});

    $self->param('stat_ar', \%s);
    $self->param('file_ar', \%r);

    # $self->disp_param(\%s); 

    return (\%s, \%r); 
} # get_stat()
#################################################################
=head2 output($sr,$rr, $out, $par)

Input variables: for output()

  $sr  - statistic hash array ref from xcopy 
  $rr  - result hash array ref containing all the files and their
         properties.
  $out - output file name. If specified, the log_file will not be used.
  $par - array ref containing parameters such as 
         log_file - log file name

Variables used or routines called: 

  from_dir   - get from_dir
  to_dir     - get to_dir
  fn_pat     - get file name pattern
  param      - get parameters
  action     - get action name 
  format_number - format time or size numbers

How to use:

  use File::XcopyD;
  my $fc = File::XcopyD->new;
  my ($s, $r) = $fc->get_stat($fdir, $tdir, 'pdf$') 
  $fc->output($s, $r); 

Return: None. 


If $out or log_file parameter is provided, then the result will be 
outputed to it.  

=cut

sub output {
    my $self = shift;
    my ($sr, $rr, $out, $par) = @_;
    my $fh = ""; 
    my $vbm = ${$par}{verbose};
 
    # print "out is :$out:  vbm= $vbm \r\n";
    if ($out) {
        $fh = new IO::File "$out", O_WRONLY|O_APPEND;
    }
    else
    {
		print "Showing the default output log since out = :$out: is void\r\n" if $vbm;  # TBDNEW 8/24/2018 
		# return;

    }
    $fh = *STDOUT if (!$fh && (!$par || ! exists ${$par}{log_file})); 
    if (!$fh && -f ${$par}{log_file}) {
        $fh = new IO::File "${$par}{log_file}", O_WRONLY|O_APPEND;
    } 
    my $fdir = $self->from_dir;
    my $tdir = $self->to_dir;
    my $fpat = $self->fn_pat;
    my $act  = $self->action;
    my $fmt  = "# %35s: %9s:%6.2f\%:%10s\n"; 
    my $ft1  = "# %15s: max %15s min %15s diff %10s\n"; 
    my $t = "";
    if (exists ${$par}{log_file})  #TBD1 log??
    {
        $t .= "# XcopyD Log File: ${$par}{log_file}\n" 
    } else
    {
	  print "Since the log_file does NOT exist:\r\n::${$par}{log_file})::  ".
	  ",below is the default log:\r\n" if $vbm;# TBDNEW 8/24/2018
        $t .= "# XcopyD Log Output\n" 
    }
    $t .= "# Date: " . localtime(time) . "\n";
    $t .= "# Input parameters: \n";
    $t .= "#   From dir: $fdir\n#    To  dir: $tdir\n";
    $t .= "#   File Pat: $fpat\n#    Action : $act\n";
    $t .= "# File statistics:           category: ";
    $t .= "    count:    pct: total size\n";
    my $n = ${$sr}{NEW}{cnt}+${$sr}{EX0}{cnt}+${$sr}{EX1}{cnt}
            +${$sr}{EX2}{cnt} ;
		# DO COUNT THE FILES ALREADY THERE AS COPIED! +${$sr}{OLD}{cnt}; 

       #$n = ($n)?$n:1;    # 1 does not make sense
       $n = ($n)?$n:0;     # so I changed it to 0
       my $nn = ($n)?$n:1; # and used this for the denominator instead to prevent 0/0

    my $m = ${$sr}{NEW}{szt}+${$sr}{EX0}{szt}+${$sr}{EX1}{szt}
            +${$sr}{EX2}{szt} +${$sr}{OLD}{szt}; 

    $t .= sprintf $fmt, ${$sr}{OK}{txt}, ${$sr}{OK}{cnt},
          100*${$sr}{OK}{cnt}/$nn,  # avoid devide by zero
          $self->format_number(${$sr}{OK}{szt}); 

		#print "VBTBD1a Above stat wrong. ::$self->format_number(${$sr}{OK}{szt}) :: but cannot solve innocuous bug\n";
		#print "VBTBD1b Above stat wrong. t so far is :: $t ::\n";

    $t .= sprintf $fmt, ${$sr}{NO}{txt}, ${$sr}{NO}{cnt},
          100*${$sr}{NO}{cnt}/$nn, 
          $self->format_number(${$sr}{NO}{szt}); 

    $t .= sprintf $fmt, ${$sr}{NEW}{txt}, ${$sr}{NEW}{cnt},
          100*${$sr}{NEW}{cnt}/$nn,
          $self->format_number(${$sr}{NEW}{szt}); 
    $t .= sprintf $fmt, ${$sr}{EX0}{txt}, ${$sr}{EX0}{cnt},
          100*${$sr}{EX0}{cnt}/$nn,
          $self->format_number(${$sr}{EX1}{szt}); 
    $t .= sprintf $fmt, ${$sr}{EX1}{txt}, ${$sr}{EX1}{cnt},
          100*${$sr}{EX1}{cnt}/$nn,
          $self->format_number(${$sr}{EX1}{szt}); 
    $t .= sprintf $fmt, ${$sr}{EX2}{txt}, ${$sr}{EX2}{cnt},
          100*${$sr}{EX2}{cnt}/$nn,
          $self->format_number(${$sr}{EX2}{szt}); 
    $t .= sprintf $fmt, ${$sr}{OLD}{txt}, ${$sr}{OLD}{cnt},
          100*${$sr}{OLD}{cnt}/$nn,
          $self->format_number(${$sr}{OLD}{szt}); 
    $t .= "# " . ("-"x35) . ": ---------:-------:----------\n";
    $t .= sprintf $fmt, "Totals", $n, 100, $self->format_number($m);
    $t .= "#\n";
    $t .= sprintf $ft1, "File size", ${$sr}{STAT}{max_size}, 
          ${$sr}{STAT}{min_size}, 
          $self->format_number(${$sr}{STAT}{szdiff},'time'); 
    $t .= sprintf $ft1, "File time", ${$sr}{STAT}{max_time}, 
          ${$sr}{STAT}{min_time}, 
          $self->format_number(${$sr}{STAT}{tmdiff},'time'); 

    # print $fh $t; # VBTBDEL original. This created an error at one point but error went away with the removal of log_file
    print "$fh $t" if $vbm; # VBTBDNEW 8/24/2018 Fixed the above with quotes

    if (!$out)
    {# TBDNEW 11/20/2018
   	print "\nXcopyD.pl: End of Xcopy report of interest\n\n" if $vbm;# TBDNEW 8/24/2018
  	# print "Total number of files matched: $m\n" if $vbm;  Has no relevence
  	print "Number of files copied with a return code expected by original creator: $n\n" if $vbm; 
  	#print "Number of files copied with a 0 return code : $g_nVB\n" if $vbm; 
  	#print "Number of files copied = $n\n";
	my $textInsert = "Number of files copied to $tdir is $n\n\n";
	&appendTextToFile('XcopyDlog.txt',$textInsert, 0);

	return;# TBDNEW 8/24/2018
    }

    $t = "#\n";  
    # action:f_time:t_time:tmdiff:f_size:t_size:szdiff:file_name
    $t .= "#action| from_time|        to_time|    tmdiff|";
    $t .= " from_size|   to_size|    szdiff|file_name";
    print $fh "$t\n";# purpose? TBD1
    my $ft2 = "%2s|%15s|%15s|%10s|%10s|%10s|%10s|%-30s\n";
    foreach my $f (sort keys %{$rr}) {
        $t = sprintf $ft2, ${$rr}{$f}{action}, 
            ${$rr}{$f}{f_time}, ${$rr}{$f}{t_time}, 
            $self->format_number(${$rr}{$f}{tmdiff},'time'),
            $self->format_number(${$rr}{$f}{f_size}), 
            $self->format_number(${$rr}{$f}{t_size}), 
            $self->format_number(${$rr}{$f}{szdiff}),
            $f; 
            print "$fh $t";# purpose? TBD1
    }
    undef $fh;
} # output
#################################################################
=head2 format_number($n,$t)

Input variables:

  $n   - a numeric number 
  $t   - number type: 
         size - in bytes or 
         time - in seconds 

Variables used or routines called: None.

How to use:

  use File::XcopyD;
  my $fc = File::XcopyD->new;
  # convert bytes to KB, MB or GB 
  my $n1 = $self->format_number(10000000);       # $n1 = 9.537MB
  # convert seconds to DDD:HH:MM:SS
  my $n2 = $self->format_number(1000000,'time'); # $n2 = 11D13:46:40

Return: formated time difference in DDDHH:MM:SS or size in GB, MB or
KB.

=cut

sub format_number {
    my $self = shift;
    my ($n, $t) = @_;
    # $n - number
    # $t - type: size or time
    #
    return "" if $n =~ /^$/; 
    $t = 'size' if ! $t;
    my ($r,$s) = ("",0); 
    my $kb = 1024;
    my $mb = 1024*$kb;
    my $gb = 1024*$mb; 
    my $mi = 60;
    my $hh = 60*$mi;
    my $dd = 24*$hh; 
    if ($t =~ /^s/i) {
        return (sprintf "%5.3fGB", $n/$gb) if $n>$gb; 
        return (sprintf "%5.3fMB", $n/$mb) if $n>$mb; 
        return (sprintf "%5.3fKB", $n/$kb) if $n>$kb; 
        return "$n Bytes"; 
    } else {
        $s = abs($n);
        if ($s>$dd) { 
            $r = sprintf "%5dD", $s/$dd; 
            $s = $s%$dd;
        }
        if ($s>$hh) {
            $r .= sprintf "%02d:", $s/$hh; 
            $s = $s%$hh;
        } 
        if ($s>$mi) {
            $r .= sprintf "%02d:", $s/$mi; 
            $s = $s%$mi;
        } 
        $r .= sprintf "%02d", $s; 
        $r  = "-$r" if ($n<0); 
    }
    return $r;
}

#################################################################
=head2 find_files($dir,$re)

Input variables:

  $dir - directory name in which files and sub-dirs will be searched
  $re  - file name pattern to be matched. 

Variables used or routines called: None.

How to use:

  use File::XcopyD;
  my $fc = File::Xcopu->new;
  # find all the pdf files and stored in the array ref $ar
  my $ar = $fc->find_files('/my/src/dir', '\.pdf$'); 

Return: $ar - array ref and can be accessed as ${$ar}[$i]{$itm}, 
where $i is sequence number, and $itm are

  file - file name without dir 
  pdir - parent dir for the file
  path - full path for the file

This method resursively finds all the matched files in the directory 
and its sub-directories. It uses C<finddepth> method from 
File::Find(1) module. 

=cut

sub find_files {
    my $self = shift;
    my $cls  = ref($self)||$self; 
    my ($dir, $re) = @_;
    my $ar = bless [], $cls; 
    my $sub = sub { 
        (/$re/)
        && (push @{$ar}, {file=>$_, pdir=>$File::Find::dir,
           path=>$File::Find::name});
    };
    finddepth($sub, $dir);
    return $ar; 
}
#################################################################
=head2 list_files($dir,$re)

Input variables:

  $dir - directory name in which files will be searched
  $re  - file name pattern to be matched. 

Variables used or routines called: None.

How to use:

  use File::XcopyD;
  my $fc = File::Xcopu->new;
  # find all the pdf files and stored in the array ref $ar
  my $ar = $fc->list_files('/my/src/dir', '\.pdf$'); 

Return: $ar - array ref and can be accessed as ${$ar}[$i]{$itm}, 
where $i is sequence number, and $itm are

  file - file name without dir 
  pdir - parent dir for the file
  path - full path for the file

This method only finds the matched files in the directory and will not
search sub directories. It uses C<readdir> to get file names.  

=cut

sub list_files {
    my $self = shift;
    my $cls  = ref($self)||$self; 
    my $ar = bless [], $cls; 
    my ($dir, $re) = @_;
    opendir DD, $dir or croak "ERR: open dir - $dir: $!\n";
    my @a = grep $re , readdir DD; 
    closedir DD; 
    foreach my $f (@a) { 
        push @{$ar}, {file=>$f, pdir=>$dir, rdir=>$f,  
            path=>"$dir/$f"};
    }
    return $ar; 
}
#################################################################
=head2 file_stat($dir,$ar)

Input variables:

  $dir - directory name in which files will be searched
  $ar  - array ref returned from C<find_files> or C<list_files>
         method. 

Variables used or routines called: None.

How to use:

  use File::XcopyD;
  my $fc = File::Xcopu->new;
  # find all the pdf files and stored in the array ref $ar
  my $ar = $fc->find_files('/my/src/dir', '\.pdf$'); 
  my $br = $fc->file_stat('/my/src/dir', $ar); 

Return: $br - hash array ref and can be accessed as ${$ar}{$k}{$itm}, 
where $k is C<rdir> and the $itm are 

  size - file size in bytes
  time - modification time in Perl time
  file - file name
  pdir - parent directory


This method also adds the following elements additional to 'file',
'pdir', and 'path' in the $ar array:

  prop - file stat array
  rdir - relative file name to the $dir
  
The following lists the elements in the stat array: 

  file stat array - ${$far}[$i]{prop}: 
   0 dev      device number of filesystem
   1 ino      inode number
   2 mode     file mode  (type and permissions)
   3 nlink    number of (hard) links to the file
   4 uid      numeric user ID of file's owner
   5 gid      numeric group ID of file's owner
   6 rdev     the device identifier (special files only)
   7 size     total size of file, in bytes
   8 atime    last access time in seconds since the epoch
   9 mtime    last modify time in seconds since the epoch
  10 ctime    inode change time (NOT creation time!) in seconds 
              sinc e the epoch
  11 blksize  preferred block size for file system I/O
  12 blocks   actual number of blocks allocated

This method converts the array into a hash array and add additional 
elements to the input array as well.

=cut

sub file_stat {
    my $s = shift;
    my $c = ref($s)||$s; 
    my ($dir, $ar) = @_; 

    my $br = bless {}, $c; 
    my ($k, $fsz, $mtm); 
    for my $i (0..$#{$ar}) {
        $k = ${$ar}[$i]{path}; 
        ${$ar}[$i]{prop} = [stat $k];
        $k =~ s{$dir}{\.};
        ${$ar}[$i]{rdir} = $k; 
        $fsz = ${$ar}[$i]{prop}[7]; 
        $mtm = ${$ar}[$i]{prop}[9]; 
        ${$br}{$k} = {file=>${$ar}[$i]{file}, size=>$fsz, time=>$mtm,
            pdir=>${$ar}[$i]{pdir}};
    }
    return $br; 
}
#################################################################

=head3  fmtTime($ptm, $otp)

Input variables:

  $ptm - Perl time
  $otp - output type: default - YYYYMMDD.hhmmss
                       1 - YYYY/MM/DD hh:mm:ss
                       5 - MM/DD/YYYY hh:mm:ss
                      11 - Wed Mar 31 08:59:27 1999

Variables used or routines called: None

How to use:

  # return current time in YYYYMMDD.hhmmss
  my $t1 = $self->fmtTime;
  # return current time in YYYY/MM/DD hh:mm:ss
  my $t2 = $self->fmtTime(time,1);

Return: date and time in the format specified.

=cut

sub fmtTime {
    my $self = shift;
    my ($ptm,$otp) = @_;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst,$r);
    #
    # Input variables:
    #   $ptm - Perl time
    #   $otp - output type: default - YYYYMMDD.hhmmss
    #                       1 - YYYY/MM/DD hh:mm:ss
    #                       5 - MM/DD/YYYY hh:mm:ss
    #                       11 - Wed Mar 31 08:59:27 1999
    # Local variables:
    #   $sec  - seconds (0~59)
    #   $min  - minutes (0~59)
    #   $hour - hours (0~23)
    #   $mday - day in month (1~31)
    #   $mon  - months (0~11)
    #   $year - year in YY
    #   $wday - day in a week (0~6: S M T W T F S)
    #   $yday - day in a year (1~366)
    #   $isdst -
    # Global variables used: None
    # Global variables modified: None
    # Calls-To:
    #   &cvtYY2YYYY($year)
    # Return: a formated time.
    # Purpose: format perl time to readable time.
    #
    if (!$ptm) { $ptm = time }
    if (!$otp) { $otp = 0 }
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        localtime($ptm);
    $year = ($year<31) ? $year+2000 : $year+1900;
    if ($otp==1) {      # output format: YYYY/MM/DD hh:mm:ss
        $r = sprintf "%04d/%02d/%02d %02d:%02d:%02d", $year, $mon+1,
            $mday, $hour, $min, $sec;
    } elsif ($otp==2) { # output format: YYYYMMDD_hhmmss
        $r = sprintf "%04d%02d%02d_%02d%02d%02d", $year, $mon+1,
            $mday, $hour, $min, $sec;
    } elsif ($otp==5) { # output format: MM/DD/YYYY hh:mm:ss
        $r = sprintf "%02d/%02d/%04d %02d:%02d:%02d", $mon+1,
            $mday, $year, $hour, $min, $sec;
    } elsif ($otp==11) {
        $r = scalar localtime($ptm);
    } else {            # output format: YYYYMMDD.hhmmss
        $r = sprintf "%04d%02d%02d.%02d%02d%02d", $year, $mon+1,
            $mday, $hour, $min, $sec;
    }
    return $r;
}
#################################################################

1;

__END__

=head1 CODING HISTORY 

=over 4

=item * Version 0.01

04/15/2004 (htu) - Initial coding

=item * Version 0.02

04/16/2004 (htu) - laid out the coding frame

=item * Version 0.06

06/19/2004 (htu) - added the inline document

=item * Version 0.10

06/25/2004 (htu) - finished the core coding and passed first testing.

=item * Version 0.11

06/28/2004 (htu) - fixed the mistakes in documentation and populated
internal variables.

=item * Version 0.12

12/15/2004 (htu) - fixed a bug in the execute method. 

12/26/2004 (htu) - added syscopy method to replace methods in 
File::Copy module. The copy method in File::Copy does not reserve the 
attributes of a file.

12/29/2004 (htu) - tested on Solaris and Win32 operating systems

8/10/2018 (vlb) fixed a bug. It did not always create destination folders as needed

8/20/2018 (vlb) fixed a bug. In the comparison of dates, it copies more than what is needed for what should be identical dates

8/25/2018 (vlb) fixed a bug. An error had occurred from a print line

8/30/2018 (vlb) Changed a default.  For Pattern, case is significant but typically, case independence is preferred

11/20/2018 (vlb) - Added the xcopy /D:<timestamp> feature via the DTG and DTGTS parameters.

=back

=head1 FUTURE IMPLEMENTATION

=over 4

=item * add directory structure checking

Check whether the from_dir and to_dir have the same directory tree.

=item * add advanced parameters 

Ssearch file by a certain date, etc.

=item * add syncronize action 

Make sure the files in from_dir and to_dir the same by copying new 
files from from_dir to to_dir, update exisitng files in to_dir, and
move files that do not exist in from_dir out of to_dir to a 
temp directory. 

=back

=head1 AUTHOR

Copyright (c) 2004 Hanming Tu.  All rights reserved.

This package is free software and is provided "as is" without express
or implied warranty.  It may be used, redistributed and/or modified
under the terms of the Perl Artistic License (see
http://www.perl.com/perl/misc/Artistic.html)

=cut

