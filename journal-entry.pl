#!/usr/bin/perl
#
# COPYRIGHT 2013 VICTOR SHULIST, OTTAWA, ONTARIO CANADA
# ALL RIGHTS RESERVED.
#
#  UPDATED: 2020.
#

use strict;
use DBI;
use Cwd;

my $thecwd = getcwd;

my $first = 1;
my @mons = qw/. January February March April May June July August September October November December/;

use DBI;
my ($pass, $brow, $mode, $db, $defcomment) = get_conf();

my $dbh = DBI->connect("DBI:mysql:$db", 'root', $pass) || die "Could not connect to database: $DBI::errstr";

foreach my $i (1..75) { print "\n"; }
my %current_balance = ();
my %types = ();

if(year_closed())
{
	print "\n\n* * THIS DATABASE'S FINANCIAL YEAR IS CLOSED.\n\n";
	<STDIN>;
	exit(1);
}

if(!does_balance_sheet_balance())
{
	print "\n\n*** BALANCE SHEET DOES NOT BALANCE!  CHECK ALL YOUR OPENING BALANCES.\n\nCAN'T MAKE ANY JOURNAL ENTRIES UNTIL IT DOES.\n\n";<STDIN>;
	exit;
}

my ($COMPANY, $CE_ACC, $RE_ACC) = get_settings();

print "\n\n---------------------------------\n\n";
print "ADDING MACHINE: Journal Entry (ver 1.000 )\n";
print "\n---------------------------------\n\n";

my $notesfile = 'notes.txt';
if(-f "$notesfile")
{
           if(!open(F,"<$notesfile")) 
           {
                print("*ERROR: there IS a $notesfile file but i cannot open it.  Press enter.\n"); 
                <STDIN>;
           }
           else
          {
                  print "---------------------------------------------- NOTE --------------------------------------\n\n";
                  foreach my $line (<F>)
                  {
                           print $line;
                  }
                   close(F);
                 print "\n-----------------------------------------------------------------------------------------------------\n";
                 print "Would you like to delete the above message? (enter 'y' or 'n'): ";
                 my $remove_note = <STDIN>;
                 chomp($remove_note);
                 if($remove_note =~ m/^[yY]/)
                {
                      unlink($notesfile);
                }
           }           
}

my ($date_valid_from, $date_valid_to, $date_end_fiscalyear) = get_valid_usingdate_range(); 

my @todayis = localtime(time);

my $TODAYTS = ( ( $todayis[5] + 1900 ) * 10**4 ) + ( ( $todayis[4] + 1 ) * 10**2 ) + $todayis[3];  

my $END_DT_TS = 0;
my $START_DT_TS = 0;

if($date_valid_from =~ m!(\d+)/(\d+)/(\d+)$!)
{  
    $START_DT_TS = ( ( $3 ) * 10**4 ) + ( ( $1 ) * 10**2 ) + $2;
}

if($date_end_fiscalyear =~ m!(\d+)/(\d+)/(\d+)$!)
{  
    $END_DT_TS = ( ( $3 ) * 10**4 ) + ( ( $1 ) * 10**2 ) + $2;
}

my $usingdate = get_using_date();

# if today would make a valid usingdate, make the usingdate today !!

if( ($TODAYTS >= $START_DT_TS) && ($TODAYTS <= $END_DT_TS ) )
{
    $usingdate = ($todayis[4] + 1).'/'.$todayis[3].'/'.( $todayis[5] + 1900 );
}

if($mode eq '')
{
    print "\n***************** mode not indicated in config file, assuming dollar mode\n\n";
    $mode = 'dollars';
}
else
{
    #print "Numeric input mode: [$mode]\n\n";
}

if(!there_are_journal_entries())
{
   #print "* NOTE: there are no journal entries made yet.  This is your chance to set all initial balances.  Once you make your first journal entry, you cannot set initial balances anymore.   You also can delete accounts right now, but not once your first entry is made.\n\n";
}

my %accounts = ();

# load accounts from database.... from 'accounts' table.
get_accounts(\%accounts);

if(!(exists $accounts{$RE_ACC}))
{
	print "\n\n****************  Retained Earnings account is defined as '$RE_ACC' - but doesn't exist, please create it.\n";	
	<STDIN>;
	exit(1);
}

if(exists $accounts{$CE_ACC})
{
	print "\n\n****************** Current Earnings account is defined as '$CE_ACC' and *DOES* exist, but it MUST NOT exist... system maintains that on its own, please remove it.\n";
	<STDIN>;
	exit(1);
}

while(1)
{
	my ($date, $comment, $debit_entries, $credit_entries, $cancel, $quitprogram) = get_journal_entry_from_user($usingdate);
	
	if($cancel == 0)
	{
		# submit entry to the database....
		post_journal_entry($date, $comment, $debit_entries, $credit_entries);		
	}

	if($quitprogram)
	{ 
		$dbh->disconnect();	
		exit(0);
	}
}

sub display_je
{
	my ($dr, $cr, $msg, $date, $comment ) = @_;

	foreach my $i (0..75) { print "\n"; }
	print $date.': '.$comment."\n\n";

	my $ln = (" " x 5);
	$ln .= (" " x 60);

	$ln .= sprintf("%15s", "Debit");	
	$ln .= sprintf("%15s", "Credit");

	print $ln."\n";
	print ("-" x 96);
	print "\n\n";

	foreach my $acc (sort { $a <=> $b } keys %{$dr})
	{
		$ln = $acc.' '.sprintf("%60s",$accounts{$acc}).' '.sprintf("%14s",c2d($dr->{$acc}));
		print $ln."\n";
			
	}
	foreach my $acc (sort keys %{$cr})
	{
		$ln = $acc.' '.sprintf("%60s", $accounts{$acc});
		$ln .= ' ';
		$ln .= (" " x 15);
		$ln .= sprintf("%14s", c2d($cr->{$acc}));
		print $ln."\n";
	}	

	print ("-" x 96)."\n";
	print "\n\n"; 	
	if($msg) 
	{
		print '>>>>>>> '.$msg;
	}
                #print "EXAMPLES (don't type the brackets ('[' and ']' in):\n\n";
                #print "To debit account 1010 by \$500, enter: [1010 500d] OR just [1010 500], so that'll increase the balance by 500\n";
                #print "To credit account 1020 by \$300, enter: [1020 300c] OR [1020 300-] so that'll decrease the balance by 300\n";
                #print "To debit account 5030 (buying something worth \$700), enter: [5030 700d] OR just [5030 700]\n";
                #print "To credit account 5010 (returning an item to store) by \$650, enter: [5010 650-] OR [5010 650c]\n";

	print "\n'p' = post entry, 'c'= cancel entry, 'q' = quit program\n\n";
}

sub get_journal_entry_from_user
{
	my %debits = ();
	my %credits = ();
	my $cancel = 0;  # =1 if user wants to cancel entry.
	my $msg = "";
	
	my $date = '';
	my $comment = '';
	my ($usingdate ) = @_;
	
	while(1)
	{
		#print "Enter date for this entry: (month/day/year) (just press enter to use $usingdate, or 'q' to quit): ";
                                $date = '';
		#$date = <STDIN>;
		chomp($date);
		$date =~ s/^\s*(.*?)\s*$/$1/;

		if($date eq '')
		{
			$date = $usingdate;	
		}	

        	if($date eq 'q') 
        	{ 
	regenerate_all_ledgers();
	balance_sheet();
	income_statement();
	produce_journal_entries();

			return (undef, undef, undef, undef, 1, 1);
        	}

		 # TODO : $date can be equal *or* earlier than $usingdate, but not after.

		if(invalid_date($date))
		{
			print "Date entered ('$date') is invalid - please enter MM/DD/YYYY\n";
		}
		else
		{
			last;
		}
	}
        	
	if($date eq '')
	{
		$date = $usingdate;
	}

	while(1)
	{
		#print "Enter comment for this entry (c = cancel): "; 
		#$comment = <STDIN>;

                                $comment = '-';
                                if($defcomment ne '') { $comment = $defcomment; }
		chomp($comment);
		$comment =~ s/^\s*(.+?)\s*$/$1/;

		if(!$comment) { next; }
		
		if($comment =~ m/^\s*[cC]\s*$/)
		{	
			return ('', '', undef, undef, 1, 0);
		}
		last;
	}

	if(length($comment) > 80)
	{
		print "*comment longer than 80, I'm cutting extra off (everything past 80 charactors), sorry buddy.\n";
		$comment = substr($comment, 0, 80);
	}

	#print "\nEnter account number and amount, end with either 'd' for debit, or 'c' for credit.";	
	
	while(1)
	{
		display_je(\%debits, \%credits, $msg, $date, $comment);
	
		my $line = <STDIN>;
		chomp($line);
		my $acc = '';
		
		if(!$line) 
		{ 
			$msg = '';
			next;
		}
		
		if($line eq 't')
		{
			print "Enter new comment:"; 
			$comment = <STDIN>;
			chomp($comment);
			next;
		}
		
		if($line eq 'd')
		{
			$msg = '';
			print "Enter new date (MM/DD/YYYY): (c = cancel)";
			my $tempdate = <STDIN>;
			chomp($tempdate);

			if($tempdate eq 'c') { next; }

			if(invalid_date($tempdate))
			{
				$msg = "Date: '$tempdate' is invalid.\n";
			}	
			else
			{
				$date = $tempdate;
			}	
			next;
		}
		
		if($line eq 'p')
		{
			if(($comment eq '-') || ( $comment =~ m/^\d+/))
                                                {
                                                              $msg = "I will post the entry, but please, enter a comment first.  Then press 'p' and press enter.";
			              next;
                                                }
			if((!(keys %debits)) and (!(keys %credits)))
			{
				$msg = 'there is nothing to post!';				
				next;
			}
			
			if(year_closed())
			{
			        $msg = "> > > > > > > >> > > > >> >  >  > This database's financial year has been closed, thus i cannot post! !!!!\n\n";
			        next;
			}
			
			if(balance(\%debits, \%credits))
			{
				return ($date, $comment, \%debits, \%credits, 0, 0);
			}
			else
			{
				$msg = "*ERR: entry does not balance, cannot post yet ('q' = quit, 'c' = cancel)\n";
				next;
			}
		}
		
		if($line eq 'c') 
		{
			return ('', '', undef, undef, 1, 0);
		}
		
		if($line eq 'q')
		{  
			regenerate_all_ledgers();
			balance_sheet();
			income_statement();
			produce_journal_entries();

			if(keys %debits)
			{  
				$msg = "you want to quit, but do you want to submit the current journal entry?\n(first post the entry ('p') OR cancel ('c') then enter quit command ('q').\n";
				next;
			}
			else
			{  
				# we are NOT in the middle of an  entry, so just exit.
				return (undef, undef, undef, undef, 1, 1);
			}
		}

		if($line =~ m/^\s*(\d{4})\s*(.+?)\s*(.)\s*$/)
		{
			my $acc = $1;
			my $amt = $2;
			my $suf = $3;
			my $operator = '';
			my $d_or_c = '';
			my $newline = $line;

			if($newline =~ m/-$/) { chop($newline); }

			if (($suf ne 'd' ) && ($suf ne 'c'))
			{
				#print "LINE [$line]\n";
				#<STDIN>;
				$operator = '+';
				if($suf  eq '-')
				{
 					$operator = '-';
				}
			
				#print "OP: [$operator]\n";
				if(($acc =~ m/^1/) || ($acc =~ m/^5/))
				{
					# Debit Account
					if($operator eq '+')
					{
						$d_or_c = 'd';  # case 1				
					}
					else
					{
						$d_or_c = 'c';
					}
				}
				else
				{
					# Credit Account
					if($operator eq '+')
					{
						$d_or_c = 'c';				
					}
					else
					{
						$d_or_c = 'd';				
					}

				}
				#print "BEFORE [$line]\n";
				$line = $newline.$d_or_c;
				#print "AFTER [$line]\n";
				#<STDIN>;
			}

		}

		if($line =~ m/^\s*(\d{4})\s*$/)
		{
			# ok user wants us to figure out the balance. .what value needs to be entered in order to balance.
			my $acc = $1;

			if(!(exists $accounts{$acc}))
			{
				%accounts = ();
				get_accounts(\%accounts);

				if(!(exists $accounts{$acc}))
				{	
					$msg = "Account '$acc' does not exist\n";
					next;
				}
			}
			
			my ($diff_amount, $diff_debit_or_credit) = diff(\%debits, \%credits);

			if($diff_debit_or_credit eq '')
			{
				$msg = 'your journal entry is already balancing :)';
				next;
			}

			delete $debits{$acc};
			delete $credits{$acc};

			my ($diff_amount, $diff_debit_or_credit) = diff(\%debits, \%credits);

			if($diff_debit_or_credit eq 'd')
			{
				$debits{$acc} = $diff_amount;
				delete $credits{$acc};
				$msg = '';	
			}
			elsif($diff_debit_or_credit eq 'c')
			{
				$credits{$acc} = $diff_amount;
				delete $debits{$acc};
				$msg = '';	
			}
			next;
		}
	
		if($line =~ m/^\s*(\d{4})\s*(.+?)\s*([dc])\s*$/)
		{
			my $acc = $1;
 
			if(!(exists $accounts{$acc}))
			{
				%accounts = ();
				get_accounts(\%accounts);

				if(!(exists $accounts{$acc}))
				{	
					$msg = "There is no account number '$acc' - check the chart of accounts.";
					next;
				}
			}
			
			my $amt = $2;
			my $doc = $3; # doc - debit or credit.

			if($amt !~ m/^\d+(\.\d*)?/)
			{
				$msg = "value '$amt' is invalid.";
				next;	
			}
			my $err;
			$amt = convert_to_cents($amt, \$err, $mode);

			if($err)
			{
			      $msg = "* value is invalid!!";
			      next;
			}
			
			if($amt == 0)
			{
				# user entered zero (0), so they want to clear this account -- i mean, they don't want this account in this journal entry.
				delete $credits{$acc};
				delete $debits{$acc}; 
				$msg = '';
				next;	
			}	

			if($doc eq 'd')
			{
				# a debit...
				$debits{$acc} = $amt;
				delete $credits{$acc};
				$msg = '';
				next;
			}
			else
			{
				# a credit...
				$credits{$acc} = $amt;
				delete $debits{$acc};
				$msg = '';
				next;
			}
		}
		else
		{
			#$msg = "Sorry, I didn't understand that.\n";
                                                 $comment = $line;
		}

		chomp($acc);
	
	}

	return ($date, $comment, \%debits, \%credits, $cancel);
}

sub diff
{
	my ($dr, $cr) = @_;
	my $total_debits = 0;
	my $total_credits = 0;

	foreach my $acc (keys %{$dr})
	{
		$total_debits += $dr->{$acc};
	}

	foreach my $acc (keys %{$cr})
	{
		$total_credits += $cr->{$acc};
	}

	if($total_debits > $total_credits)
	{
		return (($total_debits - $total_credits),'c');
	}
	elsif($total_debits < $total_credits)
	{
		return (($total_credits - $total_debits),'d');
	}
	else
	{
		return (0, '');
	}
}

sub balance
{
	# do the debits total the credits?
	my ($dr, $cr ) = @_;
	my $td = 0;
	my $tc = 0;
	
	foreach my $acc (keys %{$dr})
	{
		$td += $dr->{$acc};
	}
	foreach my $acc (keys %{$cr})
	{
		$tc += $cr->{$acc};
	}
	if($td != $tc) 
	{
		#print "$td == $tc ?\n";
		return 0;
	}
	else
	{
		return 1;
	}
}

sub get_accounts
{
	my ($ref ) = @_;
	my $sql = "SELECT number, name FROM chart_of_accounts";
	my $sth = $dbh->prepare($sql);
	run_sql("SET AUTOCOMMIT=1");

	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";

 	my @row = ();

	while(@row = $sth->fetchrow_array)
	{
		$ref->{$row[0]} = $row[1];
	}

	$sth->finish();	
}

sub invalid_date
{
	# make sure it is month, day , year, example 5/30/2013 for may 30th 2013.
	my ($date ) = @_;
	
	#print "Question: is $date between $date_valid_from , and $date_valid_to\n";
	
	my $id_y = '';
	my $id_m = '';
	my $id_d = '';
	
	my $fd_y = '';
	my $fd_m = '';
	my $fd_d = '';
	
	my $ud_y = '';
	my $ud_m = '';
	my $ud_d = '';
	
	if($date =~ m!^(\d+)/(\d+)/(\d{4})$!)
	{
	      $id_y = $3;
	      $id_m = $1;
	      $id_d = $2;
	}
	
	if($date_valid_from =~ m!^(\d+)/(\d+)/(\d{4})$!)
	{
	      $fd_y = $3;
	      $fd_m = $1;
	      $fd_d = $2;	
	}
	
	if($usingdate =~ m!^(\d+)/(\d+)/(\d{4})$!)
	{
	      $ud_y = $3;
	      $ud_m = $1;
	      $ud_d = $2;	
	}
	
	my $int_id = ($id_y) * 10000 + $id_m * 100 + $id_d;
	my $int_fd = ($fd_y) * 10000 + $fd_m * 100 + $fd_d;
	my $int_td = ($ud_y) * 10000 + $ud_m * 100 + $ud_d;
		
	if($int_id < $int_fd) { return 1; }
	if($int_id > $int_td) { return 1; }
		
	if($date =~ m!^(\d+)/(\d+)/(\d{4})$!)
	{
		my $m = $1;
		my $d = $2;
		my $y = $3;

		if(($y > 2099) or ($y < 2000))
		{
			return 1;	
		}	
		else
		{
			if($m < 1) 
			{
				return 1;
			}
			elsif($m > 12)
			{
				return 1;
			}
			else
			{
				if($d < 1)
				{
					return 1;
				}
				else
				{
					if($d > days_in_mon($y, $m))
					{
						return 1;
					}
					else
					{
						return 0;
					}
				}
			}	
		}
	}	
	else
	{
		return 1;
	}	
}

sub days_in_mon
{
	my ($y, $m) = @_;
	if(($m == 1) || ($m == 3) || ($m == 5) || ($m == 7) || ($m == 8) || ($m == 10) || ($m == 12))
	{
		return 31;
	}
	if(($m == 4) || ($m == 6) || ($m == 9) || ($m == 11))
	{
		return 30;	
	}

	if(($y % 4) == 0)
	{
		my $d = 29;
		if(($y % 100) == 0)
		{
			$d = 28;
			if(($y % 400) == 0)
			{		
				$d = 29;
			}
		} 
		return $d;
	}
	else
	{
		return 28;	
	}
}

sub run_sql
{
	my ($qry ) = @_;
	my $sth = $dbh->prepare($qry);
	$sth->execute();
	$sth->finish();
}

sub post_journal_entry
{
	my ($date, $comment, $debit_entries, $credit_entries) = @_;
	$comment =~ s/'/\\\'/g;
	
	# TODO -- use transactions !!
	
	my $fdate = $date;	
	if($fdate =~ m!^(\d+)/(\d+)/(\d{4})$!)
	{
		$fdate = $3.'-'.sprintf("%02d", $1).'-'.sprintf("%02d", $2);		
	}

	run_sql("SET AUTOCOMMIT=0");
	run_sql("START TRANSACTION");
	
	my $sql = "INSERT INTO journal_entries(transaction_date, comment) VALUES('".$fdate."', '".$comment."');";	

	my $sth = $dbh->prepare($sql);
	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	$sth->finish();	
	
	my $sql = 'SELECT LAST_INSERT_ID()';

	my $sth = $dbh->prepare($sql);
	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	my @row = $sth->fetchrow_array;
	$sth->finish();	
	
	my $jid = $row[0];
	
	foreach my $acc (keys %{$debit_entries})
	{
		my $sql = "INSERT INTO journal_entry_part(je_id, account, debiting_or_crediting, amount) VALUES(".$jid.",".$acc.",'D',".$debit_entries->{$acc}.");";
		my $sth = $dbh->prepare($sql);

		if(!$sth->execute())
		{
			run_sql("ROLLBACK");
			die "SQL error ->> ".$DBI::errstr."\n";
		}
		$sth->finish();
	}
	
	foreach my $acc (keys %{$credit_entries})
	{
		my $sql = "INSERT INTO journal_entry_part(je_id, account, debiting_or_crediting, amount) VALUES(".$jid.",".$acc.",'C',".$credit_entries->{$acc}.");";
		my $sth = $dbh->prepare($sql);

		if(!$sth->execute())
		{
			run_sql("ROLLBACK");
			die "SQL error ->> ".$DBI::errstr."\n";
		}
		$sth->finish();
	}

	run_sql("COMMIT");
	
	print "\n\n * Entry posted (entry # $jid).\n\n";
	regenerate_all_ledgers();
	balance_sheet();
	income_statement();
	produce_journal_entries();
}

sub there_are_journal_entries
{
    my $sql = 'select count(*) from journal_entries';
    my $sth = $dbh->prepare($sql);
    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
    my @row = $sth->fetchrow_array;
    if($row[0] > 0) { return 1; } else { return 0; }
    $sth->finish();
}

sub get_using_date
{
	my $sql = 'SELECT from_month, usingdate FROM dateinfo';
	my $sth = $dbh->prepare($sql);
	$sth->execute() or die "SQL error - ".$DBI::errstr."\n";
	my ($from_month, $usingdate) = $sth->fetchrow_array;
	$sth->finish();
	
	if($from_month == 0)
	{
		print "* ERR: can't make journal entries yet -- you must set fiscal year range and set using date.\n";
		print "press any key to continue...\n";
		<STDIN>;
		exit(1);
	}
	my $cd = '';
	my $y = '';
	my $m = '';
	my $d = '';

	if($usingdate =~ m/(\d{4})-(\d+)-(\d+)/)
	{
	    $cd = $2.'/'.$3.'/'.$1;
	}
	return $cd;	
}

sub get_conf
{
    my $pass='';
    my $brow='';
    my $passmentioned = 0;
    my $mode ='';
    my $db = "";
    my $dc = "";

    if(!(-f "am.conf"))
    {
	print "*ERR: no am.conf file.. please create it!\n\n";
	<STDIN>;
	exit(1);
    }	

    if(!open(F, "<am.conf"))
    {
	print "*ERR: permission problem - can't open am.conf\n\n";
                <STDIN>;
	exit(1);
    }
    my @lns = <F>;
    close(F);

    foreach my $ln (@lns)
    {
      chomp($ln);
      if($ln =~ m/^\s*browser_path\s*=\s*(.*?)\s*$/i)
      {
	  $brow = $1;
      }
      if($ln =~ m/^\s*default.comment\s*=\s*(.*?)\s*$/i)
      {
	  $dc = $1;
      }
      if($ln =~ m/^\s*db_pass\s*=\s*(.*?)\s*$/i)
      {
	  $pass = $1;
	  $passmentioned = 1;
      }
      if($ln =~ m/^\s*mode\s*=\s*(.*?)\s*$/i)
      {
	  $mode = $1;
	  $mode =~ tr/A-Z/a-z/;
      }
      if($ln =~ m/^\s*database\s*=\s*(.*?)\s*$/i)
      {
	  $db = $1;
      }
    }
    if($passmentioned == 0)
    {
	print "*ERR: db_pass not set in am.conf, please correct\n";
	<STDIN>;
	exit(1);
    }
    if($brow eq '')
    {
	print "*ERR: browser_path not set in am.conf, please correct\n";
	<STDIN>;
	exit(1);
    }
    return ($pass, $brow, $mode, $db, $dc);
}

sub get_valid_usingdate_range
{
    my $st = '';
    my $en = '';
    
    my $sql = 'SELECT from_month, from_day, usingdate, current_fiscal_year , to_month, to_day FROM dateinfo';
    
    my $sth = $dbh->prepare($sql);
    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";

    my @row = $sth->fetchrow_array;
    $sth->finish();
    
    my $f_mon = $row[0];
    my $f_day = $row[1];
    my $t_mon = '';
    my $t_day = '';
    
    my $ud = $row[2];
    my $cfy = $row[3];
    
    if($ud =~ m/(\d+)-(\d+)-(\d+)$/)
    {
	$t_mon = $2;
	$t_day = $3;
    }
    
    $st = $f_mon.'/'.$f_day.'/'.$cfy;
    my $fin = '';

    if(($t_mon == 12) && ($t_day == 31))
    {
        $en = $t_mon.'/'.$t_day.'/'.$cfy;
    }
    else
    {
        $en = $t_mon.'/'.$t_day.'/'.($cfy + 1);
    }    
  
    if( ($row[4] == 12) && ($row[5] == 31))
    {
        $fin = $row[4].'/'.$row[5].'/'.$cfy; 
    }
    else
    {
        $fin = $row[4].'/'.$row[5].'/'.($cfy + 1); 
    }
 
    return ($st, $en, $fin);
}

sub year_closed
{
	my $sql = 'SELECT year_closed, from_month FROM dateinfo';
	my $sth = $dbh->prepare($sql);
	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	my @row = $sth->fetchrow_array;
	$sth->finish();
	if($row[1] == 0)
	{
		print "\n\n** ERR: you can't make any journal entries yet.   The fiscal year start/end dates must be defined first.\n\n";
		<STDIN>;
		exit(1);
	}
	if($row[0] eq 'Y') { return 1; } else { return 0; }
}

sub convert_to_cents
{
	# take in value from user, which may or may not have decimals, and return number of cents it represents.  Also take second argument as error , set second arg ref
	# to 1 if error, 0 if ok.  3rd arg is mode, either 'dollars' or 'cents'... tells if input (arg 1) is in cents or dollars.
	
	my ($inputvallue, $err, $mode) = @_;
	chomp($inputvallue);
	$inputvallue =~ s/\s//g;
	$$err = 0;

	if($inputvallue eq '') { $$err = 1; return; }
	if($inputvallue eq '.') { $$err = 1; return; }

	if($mode eq 'cents')
	{
		if($inputvallue =~ m/\.$/)
		{	
			chop($inputvallue);
			$inputvallue .= "00";
		}
		elsif($inputvallue =~ m/^(\d*)\.(\d)$/)
		{
			$inputvallue = $1.$2.'0';
		}
		elsif($inputvallue =~ m/^(\d*)\.(\d{2})$/)
		{
			$inputvallue = $1.$2;		
		}
		elsif($inputvallue =~ m/\.\d{3,}/)
		{
			$$err = 1; return;			
		}
	}
	else
	{
		# dollars mode...

		if($inputvallue !~ m/\./)
		{
			$inputvallue .= '00';
		}	
		elsif($inputvallue =~ m/\.$/)
		{	
			chop($inputvallue);
			$inputvallue .= "00";
		}
		elsif($inputvallue =~ m/^(\d*)\.(\d)$/)
		{
			$inputvallue = $1.$2.'0';
		}
		elsif($inputvallue =~ m/^(\d*)\.(\d{2})$/)
		{
			$inputvallue = $1.$2;		
		}
		elsif($inputvallue =~ m/\.\d{3,}/)
		{
			$$err = 1; return;			
		}
	}
	
	if($inputvallue !~ m/^\d+$/)
	{
		$$err = 1; return;
	}
	return $inputvallue;
}

sub c2d
{
        # c2d - cents to dollars
        my ($in ) = @_;
        if(length($in) == 1)
        {
                return '0.0'.$in;
        }
        if(length($in) == 2)
        {
                return '0.'.$in;
        }
        elsif($in =~ m/^(\d+)(\d{2})$/)
        {
                return $1.'.'.$2;
        }
}

sub does_balance_sheet_balance
{ 
	my $A = 0; # assets
	my $LE = 0; # liabilities + equity
	
	# $A better equal $LE, or it does not balance.

	my $sql = 'select sum(initial_balance) from chart_of_accounts where (number >= 1000 and number <= 1999)';
	
	my $sth = $dbh->prepare($sql);
	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	my @row = $sth->fetchrow_array;
	$A = $row[0];
	$sth->finish();
		
	my $sql = 'select sum(initial_balance) from chart_of_accounts where (number >= 2000 and number <= 3999)';
	
	my $sth = $dbh->prepare($sql);
	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	my @row = $sth->fetchrow_array;
	$LE = $row[0];
	$sth->finish();

	my $sql = 'select sum(initial_balance) from chart_of_accounts where (number >= 2000 and number <= 2999)';
	
	my $sth = $dbh->prepare($sql);
	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	my @row = $sth->fetchrow_array;
	my $L = $row[0];
	$sth->finish();
		
	if($A == $LE)
	{
		return 1;
	}
	else
	{
		my $diff = ($A - $L); 
		print "Total equity should be $diff ( Total assets are $A, total liabilities are $L)\n";
		return 0;
	}	
}

sub get_settings
{
    my $sql = 'select display_name, current_earnings_account, retained_earnings_account from settings';
    my $sth = $dbh->prepare($sql);
    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
    my @row = $sth->fetchrow_array;
    return ($row[0], $row[1], $row[2]);
    $sth->finish();
}

sub get_fiscal_year_start_end
{
    my $st = '';
    my $en = '';
    
    my $sql = 'SELECT from_month, from_day, to_month, to_day,current_fiscal_year, usingdate FROM dateinfo';
    
    my $sth = $dbh->prepare($sql);
    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";

    my @row = $sth->fetchrow_array;
    $sth->finish();
    
    my $f_mon = $row[0];
    my $f_day = $row[1];
    my $t_mon = $row[2];
    my $t_day = $row[3];
    my $cfy = $row[4];
    my $ud = $row[5];

    $st = $f_mon.'/'.$f_day.'/'.$cfy;

    if(($t_mon == 12) && ($t_day == 31))
    {
        $en = $t_mon.'/'.$t_day.'/'.$cfy;
    }
    else
    {
        $en = $t_mon.'/'.$t_day.'/'.($cfy + 1);    
    }    
    
    return ($st, $en , $ud);
}

sub format_date
{
	my ($inp ) = @_;

	if($inp =~ m!^\s*(\d+)/(\d+)/(\d+)\s*$!)
	{
		my $m = $1;
		my $d = $2;
		my $y = $3;
		
		$m = sprintf("%02d", $m);
		$d = sprintf("%02d", $d);

		return $y.'-'.$m.'-'.$d;
	}
}

sub acc_is_doc
{
    my ($acc) = @_;

    my $debitacc = 'Credit Balance';
    my $op = 'Debit Balance';

    if(($acc >= 1000) and ($acc <= 1999)) { $debitacc = 'Debit'; $op = 'Credit';}
    if(($acc >= 5000) and ($acc <= 5999)) { $debitacc = 'Debit'; $op = 'Credit'; }

   return ($debitacc, $op);
}

sub friendlydate
{
	my ($in, $option) = @_;
	my $out = '';

	if($in =~ m/(\d{4})-(\d+)-(\d+)$/)
	{
		my $y = $1;
		my $m = $2;
		my $d = $3;
		
		my $mon = '';
		if($option eq 'short')
		{
		      $mon = substr($mons[$m], 0, 3);
		}
		else
		{
		      $mon = $mons[$m];
		}
		$out = $mon.' '.$d.', '.$y;		
	}
	return $out;
}

sub db_or_cb
{
    # debit balance (db) or credit balance (cb) ?
    # return 1 if debit balance, 2 if credit balance.
    # second item returned in list is the absolute value of $amt.
   
    my ($acc, $amt) = @_;
    my $db_or_cb = 0;
   
    my $debitacc = 0;

    if(($acc >= 1000) and ($acc <= 1999)) { $debitacc = 1; }
    if(($acc >= 5000) and ($acc <= 5999)) { $debitacc = 1; }

    if($debitacc)
    {
	if($amt >= 0)
	{
	    $db_or_cb = 1;
	}
	else
	{
	  $db_or_cb = 2;
	}
    }
    else
    {
	if($amt >= 0)
	{
          $db_or_cb = 2;
	}
      else
      {
          $db_or_cb = 1;
      }
    }  
   
    return $db_or_cb;
}

sub negative
{
    my ($doc, $acc) = @_;
    # should this value be submited to the database as a negative ?
    # if account ($acc) is a debit account and we're saying it has a credit balance ($doc eq 'c'), then it is negative, otherwise positive.
    # likewaise, if account is a credit account, but saying it is debit balance, its negative, else positive.

    my $debitacc = 0;

    if(($acc >= 1000) and ($acc <= 1999)) { $debitacc = 1; }
    if(($acc >= 5000) and ($acc <= 5999)) { $debitacc = 1; }

    if($debitacc)
    {
	if($doc eq 'd')
	{
	    return 0;
	}
	else
	{
	    return 1;
	}
    }
    else
    {
	if($doc eq 'd')
	{
	      return 1;
	}
	else
	{
	      return 0;
	}
    }    
}

sub generate_ledger_for
{
	my ($acc ) = @_;
	my ($fiscal_start, $fiscal_end , $usingdate) = get_fiscal_year_start_end();

	$fiscal_start = format_date($fiscal_start);
	$fiscal_end = format_date($fiscal_end);

		my $sql = "select transaction_date, amount, debiting_or_crediting, je_id, comment from journal_entry_part inner join journal_entries on journal_entry_part.je_id = journal_entries.id where account = $acc and journal_entries.transaction_date >= '$fiscal_start' and journal_entries.transaction_date <= '$fiscal_end' order by je_id asc, transaction_date asc";

		my $init = get_opening_balance($acc);
		my $bal = $init;

		my $sth = $dbh->prepare($sql);

		$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";

		my @row = ();
		my $html = '';

		$html = '<html><head><style type="text/css"> th { font-family:arial; color:#FFFFFF; background-color: #506A9A; font-weight: normal;} h2 { font-family:arial; color: #506A9A; font-weight: bold;} h4 { font-family:arial; color: #506A9A; font-weight: bold;} h1 { font-family:arial; color: #506A9A; font-weight: bold;} h3 { font-family:arial; color: #506A9A; font-weight: bold;} h5 { font-family:arial; color: #506A9A; font-weight: bold;} td { font-family:arial; background-color: #BACCFF; font-weight: normal;} td.number { font-family:arial;; text-align:right; } table.border { #506a9a solid;}
</style></head>';

		$html .= '<body font="arial"><center><a href="file://'.$thecwd.'/balance.html'.'">Balance Sheet</a>';
		$html .= '<h1>Ledger for account '.$acc.': '.$accounts{$acc}."<br></h1><h3><b>For period $fiscal_start to $fiscal_end</b></h3>";

		my ($baltype, $baltypeop) = acc_is_doc($acc);

		if($init > 0)
		{
			$html .= '<h3>Opening balance: '.c2d($init).' '.$baltype.'</h3><BR>';
		}
		else
		{
			$init *= (-1);
			$html .= '<h3>Opening balance: '.c2d($init).' '.$baltypeop.'</h3><BR>';
		}

		$html .= '<table cellpadding="10px">';
		$html .= '<tr><th>&nbsp</th><th>Date</th><th>JE #</th><th>Comment</th><th>Debit</th><th>Credit</th><th>Debit Balance</th><th>Credit Balance</th></tr>';

		while(@row = $sth->fetchrow_array)
		{
			my $date = $row[0];
			my $amt = $row[1];
			my $oamt = $amt;
			my $doc = $row[2];	
			my $jenum = $row[3];
			my $comment = $row[4];

			$doc =~ tr/A-Z/a-z/;

			if(negative($doc, $acc))
			{	
				$amt = (-1) * $amt;	
			}
			
			$bal += $amt;
			my $abs_bal = abs($bal);
			
			if($doc eq 'd')
			{  
				if(db_or_cb($acc, $bal) == 1)
				{
					$html .= '<tr><td><a href="file://'.$thecwd.'/balance.html'.'">Balance</a></td>';
					$html .= '<td>'.friendlydate($date,"short").'</td>';
					#$html .= '<td>'.$jenum.'</td>';
					$html .=  '<td><a href="file://'.$thecwd.'/LIST_OF_JOURNAL_ENTRIES.html#je'.$jenum.'">'.$jenum.'</a></td>';
					$html .= '<td>'.$comment.'</td>';
					$html .= '<td align="right">'.c2d($oamt).'</td>';   # debit
					$html .= '<td>&nbsp</td>';       # credit
					$html .= '<td align="right">'.c2d($abs_bal).'</td>';    # debit balance	
					$html .= '<td>&nbsp</td>';       # credit balance
				}
				else
				{
					$html .= '<tr><td><a href="file://'.$thecwd.'/balance.html'.'">Balance</a></td>';
					$html .= '<td>'.friendlydate($date,"short").'</td>';
					#$html .= '<td>'.$jenum.'</td>';
					$html .=  '<td><a href="file://'.$thecwd.'/LIST_OF_JOURNAL_ENTRIES.html#je'.$jenum.'">'.$jenum.'</a></td>';					
					$html .= '<td>'.$comment.'</td>';
					$html .= '<td align="right">'.c2d($oamt).'</td>';   # debit
					$html .= '<td>&nbsp</td>';       # credit
					$html .= '<td>&nbsp</td>';       # debit balance
					$html .= '<td align="right">'.c2d($abs_bal).'</td>';    # credit balance	
				}
			}	
			else
			{
				if(db_or_cb($acc, $bal) == 1)
				{
					$html .= '<tr><td><a href="file://'.$thecwd.'/balance.html'.'">Balance</a></td>';
					$html .= '<td>'.friendlydate($date,"short").'</td>';
					#$html .= '<td>'.$jenum.'</td>';
					$html .=  '<td><a href="file://'.$thecwd.'/LIST_OF_JOURNAL_ENTRIES.html#je'.$jenum.'">'.$jenum.'</a></td>';
					$html .= '<td>'.$comment.'</td>';
					$html .= '<td>&nbsp</td>';   # debit
					$html .= '<td align="right">'.c2d($oamt).'</td>';       # credit
					$html .= '<td align="right">'.c2d($abs_bal).'</td>';    # debit balance	
					$html .= '<td>&nbsp</td>';       # credit balance
				}
				else
				{
					$html .= '<tr><td><a href="file://'.$thecwd.'/balance.html'.'">Balance</a></td>';
					$html .= '<td>'.friendlydate($date,"short").'</td>';
					#$html .= '<td>'.$jenum.'</td>';
					$html .=  '<td><a href="file://'.$thecwd.'/LIST_OF_JOURNAL_ENTRIES.html#je'.$jenum.'">'.$jenum.'</a></td>';
					$html .= '<td>'.$comment.'</td>';
					$html .= '<td>&nbsp</td>';   # debit
					$html .= '<td align="right">'.c2d($oamt).'</td>';       # credit
					$html .= '<td>&nbsp</td>';    # debit balance	
					$html .= '<td align="right">'.c2d($abs_bal).'</td>';       # credit balance
				}
			}
		}
		
		$html .= '</table><h2><a name="bottom" href="file://'.$thecwd.'/balance.html'.'">BALANCE SHEET</a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href="file://'.$thecwd.'/income.html'.'">INCOME/EXPENSE</a></h2>';
		$html .= '</center></body>';
		$html .= '</html>';

		my $temp = 'ledger_'.$acc.'.html';

		if(-f "$temp")
		{
			unlink("$temp");
			if(-f "$temp")
			{
				print "I can't delete '$temp' !!\n";
				exit(1);
			}
		}	
		if(!open(F, ">$temp"))
		{
			print "*ERR: can't open '$temp' for writing.\n";
			exit(1);
		}	
		print F $html;
		close(F);
		$sth->finish(); 
}

sub get_opening_balance
{
	my ($acc) = @_;
	my $sql = "SELECT initial_balance FROM chart_of_accounts WHERE number = $acc";
	my $sth = $dbh->prepare($sql);

	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	my @row = ();
	@row = $sth->fetchrow_array;

	$sth->finish(); 
	return $row[0];
}

sub regenerate_all_ledgers
{
			      my $sql = "SELECT number FROM chart_of_accounts";
			      my $sth = $dbh->prepare($sql);
			      $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";

			      my @row;
			      while(@row = $sth->fetchrow_array)
			      {
					generate_ledger_for($row[0]);
			      } 
			$sth->finish(); 
}

sub acc_is_debit
{
    my ($acc) = @_;

    if(($acc >= 1000) and ($acc <= 1999)) { return 1; }

    if(($acc >= 5000) and ($acc <= 5999)) { return 1; }

    return 0;
}

sub balance_sheet
{  
    %current_balance = ();
    %accounts = ();
    %types = ();
    get_accounts(\%accounts,  \%types);
    get_bals(\%current_balance);

    my $current_earnings = income_statement(\%current_balance, \%accounts, \%types);
    my $current_earnings_display = displaybal($current_earnings);

    my $assets_html = '';
    my $liabilities_html = '';
    my $equity_html = '';

    $assets_html = '<h3>Assets</h3><table cellpadding="2px">';
    $liabilities_html = '<h3>Liabilities</h3><table>';
    $equity_html = '<h3>Equity</h3><table>';

    my $total_assets = 0;
    my $total_liabilities = 0;
    my $total_equity = 0;

    my $subtotal = 0;
    my $prevtype = '';

    foreach my $acc (1000..1999)
    {
	if(!(exists $accounts{$acc})) { next; }

	my $val_balance = $current_balance{$acc}->[0];
	my $display_balance = $current_balance{$acc}->[1];

	$total_assets += $val_balance;
 
	my $type = $types{$acc};
	$type =~ tr/a-z/A-Z/;

	if($type eq 'R')
	{
	      if($prevtype eq 'L')
	      {
		  $assets_html  .= '<tr><td width="250px">&nbsp</td><td align="right">-------------------</td><td>&nbsp;</td></tr>';
		  $assets_html  .= '<tr><td width="250px">&nbsp</td><td align="right">'.displaybal($subtotal).'</td><td>&nbsp;</td></tr>';
	      }

	      $assets_html  .= '<tr><td width="250px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td>&nbsp;</td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'.$display_balance. '</a></td></tr>';

	      #$assets_html  .= '<tr><td width="250px">'.$acc.' '.$accounts{$acc}.'</td><td>&nbsp;</td><td align="right">'.$display_balance.'</td></tr>';
	      $subtotal = 0;
	}
	else
	{
	      $subtotal += $val_balance;
	      $assets_html  .= '<tr><td width="250px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'.$display_balance.'</a></td><td>&nbsp;</td></tr>';
	}
	
	$prevtype = $type;
    }

    if($prevtype eq 'L')
    {
	$assets_html .= '<tr><td width="250px">&nbsp</td><td align="right">-------------------</td><td>&nbsp;</td></tr>';
	$assets_html .= '<tr><td width="250px">&nbsp</td><td align="right">'.displaybal($subtotal).'</td><td>&nbsp;</td></tr>';
    }

    $assets_html .= '<tr><td width="250px">&nbsp</td><td>&nbsp</td><td align="right"><h3>&nbsp</h3></td><td>&nbsp;</td></tr>';

    $assets_html .= '</table>';

    my $subtotal = 0;
    my $prevtype = '';

    foreach my $acc (2000..2999)
    {
	if(!(exists $accounts{$acc})) { next; }

	my $val_balance = $current_balance{$acc}->[0];
	my $display_balance = $current_balance{$acc}->[1];

	$total_liabilities += $val_balance;
 
	my $type = $types{$acc};
	$type =~ tr/a-z/A-Z/;

	if($type eq 'R')
	{
	      if($prevtype eq 'L')
	      {
		  $liabilities_html .= '<tr><td width="250px">&nbsp</td><td align="right">-------------------</td><td>&nbsp;</td></tr>';
		  $liabilities_html .= '<tr><td width="250px">&nbsp</td><td align="right">'.displaybal($subtotal).'</td><td>&nbsp;</td></tr>';
	      }

	      $liabilities_html .= '<tr><td width="250px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td>&nbsp;</td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'.$display_balance. '</a></td></tr>';

	      #$liabilities_html .= '<tr><td width="250px">'.$acc.' '.$accounts{$acc}.'</td><td>&nbsp;</td><td align="right">'.$display_balance.'</td></tr>';
	      $subtotal = 0;
	}
	else
	{
	      $subtotal += $val_balance;
	      $liabilities_html .= '<tr><td width="250px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'.$display_balance.'</a></td><td>&nbsp;</td></tr>';
	}
	$prevtype = $type;
    }

    if($prevtype eq 'L')
    {
	$liabilities_html .= '<tr><td width="250px">&nbsp</td><td align="right">-------------------</td><td>&nbsp;</td></tr>';
	$liabilities_html .= '<tr><td width="250px">&nbsp</td><td align="right">'.displaybal($subtotal).'</td><td>&nbsp;</td></tr>';
    }

    $liabilities_html .= '<tr><td width="250px">&nbsp</td><td>&nbsp</td><td align="right"><h3>&nbsp</h3></td><td>&nbsp;</td></tr>';

    $liabilities_html .= '<tr><td width="250px"><h3>Total Liabilities</h3></td><td>&nbsp</td><td align="right"><h3>'.displaybal($total_liabilities).'</h3></td><td>&nbsp;</td></tr>';

    $liabilities_html .= '</table>';

    my $subtotal = 0;
    my $prevtype = '';

    foreach my $acc (3000..3999)
    {
	if($acc == $CE_ACC)
	{
	    $total_equity += $current_earnings;
	    $equity_html .= "<tr><td width='250p'>$CE_ACC Current Earnings</td><td>&nbsp;</td><td align='right'>".displaybal($current_earnings)."</td></tr>";		
	    next;
	}

	if(!(exists $accounts{$acc})) { next; }

	my $val_balance = $current_balance{$acc}->[0];
	my $display_balance = $current_balance{$acc}->[1];

	$total_equity += $val_balance;
 
	my $type = $types{$acc};
	$type =~ tr/a-z/A-Z/;

	if($type eq 'R')
	{
	      if($prevtype eq 'L')
	      {
		  $equity_html .= '<tr><td width="250px">&nbsp</td><td align="right">-------------------</td><td>&nbsp;</td></tr>';
		  $equity_html .= '<tr><td width="250px">&nbsp</td><td align="right">'.displaybal($subtotal).'</td><td>&nbsp;</td></tr>';
	      }

	      $equity_html .= '<tr><td width="250px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td>&nbsp;</td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'.$display_balance.'</a></td></tr>';
	      $subtotal = 0;
	}
	else
	{
	      $subtotal += $val_balance;
	      $equity_html .= '<tr><td width="250px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'.$display_balance.'</a></td><td>&nbsp;</td></tr>';
	}
	$prevtype = $type;
    }

    if($prevtype eq 'L')
    {
	$equity_html .= '<tr><td width="250px">&nbsp</td><td align="right">-------------------</td><td>&nbsp;</td></tr>';
	$equity_html .= '<tr><td width="250px">&nbsp</td><td align="right">'.displaybal($subtotal).'</td><td>&nbsp;</td></tr>';
    }

    $equity_html .= '<tr><td width="250px">&nbsp</td><td>&nbsp</td><td align="right"><h3>&nbsp</h3></td><td>&nbsp;</td></tr>';

    $equity_html .= '<tr><td width="250px"><h3>Total Equity</h3></td><td>&nbsp</td><td align="right"><h3>'.displaybal($total_equity).'</h3></td><td>&nbsp;</td></tr>';

    $equity_html .= '</table>';

    my $fn = 'balance.html';
        
    my $total_assets_html = '<table><tr><td width="250px"><h2><u>Total Assets</u></h2></td><td>&nbsp</td><td align="right"><h2><u>'.displaybal($total_assets).'</u></h2></td><td>&nbsp;</td></tr></table>';
    my $total_lande_html = '<table><tr><td width="250px"><h2><u>Total Liabilities & Equity</u></h2></td><td>&nbsp</td><td align="right"><h2><u>'.displaybal($total_liabilities + $total_equity).'</u></h2></td><td>&nbsp;</td></tr></table>';

   my $INC_PATH = 'file://'.$thecwd.'/income.html';
   my $LIST_OF_JOURNAL_ENTRIES = 'file://'.$thecwd.'/LIST_OF_JOURNAL_ENTRIES.html#bottom';
    
    my $html = "<html><title>BALANCE SHEET</title><body><h1>$COMPANY</h1><br><a href='___INC_PATH___' ><b>INCOME STATEMENT</b></a>&nbsp;&nbsp;&nbsp;&nbsp;<a href='___LIST_OF_JOURNAL_ENTRIES___' ><b>LIST OF ENTRIES</b></a><table border='0'><tr><td valign='top'><br>$assets_html</td><td valign='top'>$liabilities_html</td></tr><tr><td>&nbsp</td><td valign ='top'>$equity_html</td></tr><tr><td>$total_assets_html</td><td>$total_lande_html</td></tr></table></body></html>";
    $html =~ s/___INC_PATH___/$INC_PATH/g;
    $html =~ s/___LIST_OF_JOURNAL_ENTRIES___/$LIST_OF_JOURNAL_ENTRIES/g;
    
    if(-f "$fn")
    {
	unlink("$fn");

	if(-f "$fn")
	{
	    print "\n\n** ERR: can't delete '$fn'\n";
	    <STDIN>;
	    exit(1);
	}
    }

    if(!open(F, ">$fn"))
    {
	print "\n\n*** ERR: can't write to file '$fn'\n";
	<STDIN>;
	exit(1);
    }

    print F $html; 
    close(F);

}

sub get_bals
{
	my ($ref ) = @_;
    	my @row = ();
	
	my $sql = 'select number, initial_balance from chart_of_accounts';
    	my $sth = $dbh->prepare($sql);
    	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
    	my %ob = (); # opening balances.
    	
	while(@row = $sth->fetchrow_array)
    	{
	    $ob{$row[0]} = $row[1];
    	}
    	$sth->finish();
		
	my $sql = 'select account, debiting_or_crediting, amount from journal_entry_part';
    	my $sth = $dbh->prepare($sql);
    	$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	my %info = ();
	
	while(@row = $sth->fetchrow_array)
	{
		push @{$info{$row[0]}}, [ $row[1], $row[2] ];
	}

    	$sth->finish();

	
    	foreach my $acc (keys %ob)
    	{
		if($ob{$acc} > 0)
		{
			$ref->{$acc} = [ $ob{$acc}, c2d($ob{$acc}) ]; 			
		}
		elsif($ob{$acc} < 0)
		{
			$ref->{$acc} = [ $ob{$acc}, '('.c2d((-1) * $ob{$acc}).')' ]; 					
		}
		else 
		{
			$ref->{$acc} = [ 0, '0.00' ]; 							
		}
    	}
    	
	foreach my $acc (keys %info)
	{
		my $d = 0;
		my $c = 0;
		
		if(acc_is_debit($acc))
		{
			if($ob{$acc} > 0)
			{
				$d = $ob{$acc};
			}
			elsif($ob{$acc} < 0)
			{
				$c = (-1) * $ob{$acc};
			}
		}	
		else
		{
			if($ob{$acc} > 0)
			{
				$c = $ob{$acc};
			}
			elsif($ob{$acc} < 0)
			{
				$d = (-1) * $ob{$acc};
			}

		}	
	
		foreach my $ref (@{$info{$acc}})
		{
			my $doc = $ref->[0];
			my $amt = $ref->[1];
			
			if($doc eq 'D')
			{
				$d += $amt;	
			}
			else
			{
				$c += $amt;	
			}
		}

		if($d > $c)
		{
			my $diff = $d - $c;
			
			if(acc_is_debit($acc))
			{
				$ref->{$acc} = [$diff, c2d($diff) ];
			}
			else
			{
				$ref->{$acc} = [ (-1) * $diff, '('.c2d($diff).')' ];
			}
		}
		elsif($c > $d)
		{
			my $diff = $c - $d;
			
			if(acc_is_debit($acc))
			{
				$ref->{$acc} = [ (-1) * $diff, '('.c2d($diff).')' ];
			}
			else
			{
				$ref->{$acc} = [$diff, c2d($diff) ];
			}
		}
		else
		{
			$ref->{$acc} = [ 0, '0.00' ]; 
		}
	}
}

sub income_statement
{
    my ($balref , $accref, $typesref) = @_;

    if(($balref) && ($accref) && ($typesref)) 
    {
	%current_balance = %{$balref};
	%accounts = %{$accref};
	%types = %{$typesref};
    }
    else
    {
	%current_balance = ();
	%accounts = ();
	%types = ();

	get_accounts(\%accounts,  \%types);
	get_bals(\%current_balance);
  
    }

    # income first
    my $total_income = 0;
    my $total_expense = 0;
    my $net_income = 0;

    my $html = '';
    $html .= '<html><title>INCOME STATEMENT</title>';
    $html .= '<body>';
    $html .= '<h1>'.$COMPANY.'</h1><h2><a href="file://'.$thecwd.'/balance.html'.'">Click here to go back to Balance Sheet</a></h2>';
   
    my $income_html .= '<h2>Income</h2><table><tr><td></td><td></td><td></td></tr>';
    my $expense_html = '<h2>Expense</h2><table><tr><td></td><td></td><td></td></tr>';

    foreach my $acc (4000..4999)
    {
	if(!(exists $accounts{$acc})) { next; }

	my $val_balance = $current_balance{$acc}->[0];

	my $display_balance = $current_balance{$acc}->[1];

	$total_income += $val_balance;
 
	my $type = $types{$acc};

	$type =~ tr/a-z/A-Z/;

	if($type eq 'R')
	{
	      $income_html .= '<tr><td width="450px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td>&nbsp;</td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'.$display_balance.'</a></td></tr>';
	}
	else
	{
	      $income_html .= '<tr><td width="450px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'. $display_balance.'</a></td><td>&nbsp;</td></tr>';
	}
    }

    $income_html .= '<tr><td width="450px">&nbsp</td><td>&nbsp</td><td align="right">----------------------</td></tr>';
    $income_html .= '<tr><td width="450px"><b>Total Income</b></td><td>&nbsp</td><td align="right">'.displaybal($total_income).'</td></tr>';

    $income_html .= '</table>';

    foreach my $acc (5000..5999)
    {
	if(!(exists $accounts{$acc})) { next; }

	my $val_balance = $current_balance{$acc}->[0];

	my $display_balance = $current_balance{$acc}->[1];

	$total_expense += $val_balance;
 
	my $type = $types{$acc};

	$type =~ tr/a-z/A-Z/;

	if($type eq 'R')
	{
		$expense_html.= '<tr><td width="450px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td>&nbsp;</td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'.$display_balance.'</a></td></tr>';
	}
	else
	{
	      $expense_html .= '<tr><td width="450px"><a href="ledger_'.$acc.'.html#bottom">'.$acc.' '.$accounts{$acc}.'</a></td><td align="right"><a href="ledger_'.$acc.'.html#bottom">'. $display_balance.'</a></td><td>&nbsp;</td></tr>';
	}
    }

    if($balref)
    {
	return($total_income - $total_expense);
    }

    $expense_html .= '<tr><td width="450px">&nbsp</td><td>&nbsp</td><td align="right">----------------------</td></tr>';
    $expense_html .= '<tr><td width="450px"><b>Total Expense</b></td><td>&nbsp</td><td align="right">'.displaybal($total_expense).'</td></tr>';

    $expense_html .= '<tr><td width="450px"><b>&nbsp</b></td><td>&nbsp</td><td align="right">&nbsp</td></tr>';
    $expense_html .= '<tr><td width="450px"><b><h2><u>Net Income</u></h2></b></td><td>&nbsp</td><td align="right"><h2>'.displaybal($total_income - $total_expense).'</h2></td></tr>';

    $expense_html .= '</table>';

    $html .= '<div align="top">'.$income_html.'</div><div align="top">'.$expense_html.'</div';
   
    $html .= '</font></body>';
    $html .= '</html>';

    my $fn = 'income.html';

    if(-f "$fn")
    {
	unlink("$fn");

	if(-f "$fn")
	{
	    print "\n\n** ERR: can't delete '$fn'\n";
	    <STDIN>;
	    exit(1);
	}
    }

    if(!open(F, ">$fn"))
    {
	print "\n\n*** ERR: can't write to file '$fn'\n";
	<STDIN>;
	exit(1);
    }

    print F $html; 
    close(F);

}

sub displaybal
{
    my ($v) = @_;
  
    if($v < 0) 
    { 
	return '('.c2d(abs($v)).')';
    }
    else
    {
	return c2d($v);
    }   
}

sub produce_journal_entries
{
		my $sql = 'select journal_entries.id, transaction_date, comment, account, debiting_or_crediting, amount from journal_entries inner join journal_entry_part where journal_entries.id = journal_entry_part.je_id order by journal_entries.id asc, debiting_or_crediting desc';
		my $html = '<html><title>LIST OF ENTRIES</title></a><head><style type="text/css"> th { font-family:arial; color:#FFFFFF; background-color: #506A9A; font-weight: normal;} h2 { font-family:arial; color: #506A9A; font-weight: bold;} h4 { font-family:arial; color: #506A9A; font-weight: bold;} h1 { font-family:arial; color: #506A9A; font-weight: bold;} h3 { font-family:arial; color: #506A9A; font-weight: bold;} h5 { font-family:arial; color: #506A9A; font-weight: bold;} td { font-family:arial; background-color: #BACCFF; font-weight: normal;} td.number { font-family:arial;; text-align:right; } table.border { #506a9a solid;}
</style></head><body style="font-size:14pt"><center><h2><font color="#FF0000"
>Victor & Melanie</font>&nbsp;<font color="#000000"></font> Inc: Journal entries.</h2>';

		my $sth = $dbh->prepare($sql);
		$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";

		my $pje = '';
		my $totald = 0;
		my $totalc = 0;
		my @row = ();
		my $je_html = '';
		my @debs = ();
		my @creds = ();
		my $pdate = '';
		my $pcomment = '';
		my $fd = '';

		while(@row = $sth->fetchrow_array)
		{ 
			my $je_num = $row[0];
			my $date = $row[1];
			my $comment = $row[2];
			my $account_number = $row[3];
			my $account_name = $accounts{$row[3]};
			my $doc = $row[4]; # debit or credit? 'D' or 'C'
			my $amount = $row[5];

			if(($je_num != $pje) && ($pje))
			{
				# done getting all info for this entry...
		
		                                   $je_html = '<a href="file://'.$thecwd.'/balance.html'.'"><b>* *Click here to go back to Balance Sheet</b></a>';
				$je_html .= '<h4><u><a name="je'.$pje.'">Entry # '.$pje.' on '.$pdate.' "'.$pcomment.'"</a></u></h4>';

				$je_html .= "<table cellpadding='10px' style='font-size:12pt'>";
				$je_html .= '<tr><th width="425px">Account</th><th width="80px">Debit</th><th width="80px">Credit</th></tr>';
	
				foreach my $deb (@debs)
				{
					$je_html .= '<tr><td>'.($deb->[0]).'</td><td align="right">'.c2d($deb->[1]).'</td><td>&nbsp;</td></tr>';
				}

				foreach my $cred (@creds)
				{
					$je_html .= '<tr><td>'.($cred->[0]).'</td><td>&nbsp</td><td align="right">'.c2d($cred->[1]).'</td></tr>';
				}

				$je_html .= '<tr><td width="425px">&nbsp</td><td align="right"><b><u>'.c2d($totald).'</u></b></td><td align="right"><b><u>'.c2d($totalc).'</u></b></td></tr>';

				$je_html .= '</table><br><br>';
				$html .= $je_html;

				$je_html = '';
				@debs = ();
				@creds = ();
				$totalc = 0;
				$totald = 0;
			}

			if($doc eq 'D') 
			{
				push @debs, [$account_number.' "'.$account_name.'"', $amount ];	
				$totald += $amount; 
			}
			if($doc eq 'C') 
			{ 
				push @creds, [$account_number.' "'.$account_name.'"', $amount ];	
				$totalc += $amount; 
			}
		
			$pje = $je_num;
			$pcomment = $comment;
			$pdate = friendlydate($date);
 
		}

		if(!@debs)
		{
			print "\n\n********************************************************* No journal entries were made so far.\n\n";
			next;
		}

	                  $je_html  .=  '<h4><u><a name="je'.$pje.'">Entry # '.$pje.' on '.$pdate.' "'.$pcomment.'"</a></u></h4>';
		#$je_html .= '<h4><u>Entry # '.$pje.' on '.$pdate.' "'.$pcomment.'"</u></h4>';
		$je_html .= "<table cellpadding='10px' style='font-size:12pt'>";
		$je_html .= '<tr><th width="425px">Account</th><th width="80px">Debit</th><th width="80px">Credit</th></tr>';
	
		foreach my $deb (@debs)
		{
			$je_html .= '<tr><td>'.($deb->[0]).'</td><td align="right">'.c2d($deb->[1]).'</td><td>&nbsp;</td></tr>';
		}

		foreach my $cred (@creds)
		{
			$je_html .= '<tr><td>'.($cred->[0]).'</td><td>&nbsp</td><td align="right">'.c2d($cred->[1]).'</td></tr>';
		}

		$je_html .= '<tr><td>&nbsp</td><td align="right"><b><u>'.c2d($totald).'</u></b></td><td align="right"><b><u>'.c2d( $totalc).'</u></b></td></tr>';

		$je_html .= '</table><br><br>';
		$html .= $je_html;
		$html .= '<center><h2><a name="bottom" href="file://'.$thecwd.'/balance.html'.'">Click here to go back to Balance Sheet</a>';

		$sth->finish();
		$html .= '</font></center></body></html>';
		
		my $temp = 'LIST_OF_JOURNAL_ENTRIES.html';

		if(!open(F, ">$temp"))
		{
		    print "\n\n***************************************************** ERR: can't write to file '$temp'\n\n";
			return;		
		}
		
		print F $html;
		close(F);		
}
