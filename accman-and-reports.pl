#!/usr/bin/perl
#
# COPYRIGHT 2013 VICTOR SHULIST, OTTAWA, ONTARIO CANADA
# ALL RIGHTS RESERVED.
#
use strict;
use DBI;

my @mons = qw/. January February March April May June July August September October November December/;

my ($pass, $brow, $mode,$db) = get_conf();

if($db eq '')
{
    print "**ERR: no 'database' given in config file !!!\n";
   <STDIN>;
    exit;
}

my %accounts = ();
my %types = ();
my %current_balance = ();

foreach my $i (1..75) { print "\n"; }

my $dbh = DBI->connect("DBI:mysql:$db", 'root', $pass) || die "Could not connect to database: $DBI::errstr";

get_accounts(\%accounts, \%types);

my ($fiscal_start, $fiscal_end , $usingdate) = get_fiscal_year_start_end();

# current earnings and retained earnings accounts... (special accounts)....
my ($COMPANY, $CE_ACC, $RE_ACC) = get_settings();

$COMPANY = '<font face="arial" color="#FF0000">Victor & Melanie</font>&nbsp;<font face="arial" color="#000000"></font> Inc';

sub exit_prog
{
	my ($dbh) = @_;
	$dbh->disconnect();
	exit(0);
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

sub there_are_journal_entries
{
    my $sql = 'select count(*) from journal_entries';
    my $sth = $dbh->prepare($sql);
    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
    my @row = $sth->fetchrow_array;
    if($row[0] > 0) { return 1; } else { return 0; }
    $sth->finish();
}

my $msg = '';

while(1)
{
	foreach my $i (1..75) { print "\n"; }
	print "\n* * * * * * * ADDING MACHINE ver 0.9952 * * * * * * * * *\n\n";
	print "(input mode: $mode)\n\n\n";

	if($msg) { print $msg."\n"; }

	if(there_are_journal_entries())
	{
		print "L) Ledger report\n\n";
	}

	print "J) Journal entries report\n\n";

	print "C) Chart of accounts (with opening balances)\n\n";

	print "I) Income statement\n\n";

	print "B) Balance sheet\n\n";

	if(!there_are_journal_entries())
	{
	    print "S) Set initial balances.\n\n";
	    
	    print "D) Define special accounts (retained earnings) and (current earnings)\n\n";

	    if(!fy_set())
	    {
		print "F) Fiscal Year setting\n\n";
	    }

	    print "Y) Year forward (close books for this year, create new database for new year)\n\n";
	}
	else
	{
	    print "Y) Year forward (close books for this year, create new database for new year)\n\n";
	}

	if(fy_set())
	{
	    print "U) Using date (push your default using date up)\n\n";
	}

	print "N) change company name for this database\n\n";

	print "Q) Quit program\n\n";

	print "\n\n";

	print "Enter your choice: "; 

	my $ch = <STDIN>;

	chomp($ch);

	$ch =~ tr/A-Z/a-z/;

	if($ch eq 'y')
	{
		# CLOSE BOOKS  ..  Rememinder -- set year_closed = Y in dateinfo.
	}
	
	if($ch eq 'n')
	{
	    change_company_name();
	    next;
	}

	if($ch eq 'i')
	{
	      income_statement();
	      next;
	}
	
	if($ch eq 'b')
	{
	      balance_sheet();
	      next;
	}
	
	if($ch eq 'f')
	{
		if(fy_set())
		{
		      print "\n\n************************************ ERROR: fiscal year already set, can't be changed now.\n";
		      next;
		}

		if(there_are_journal_entries())
		{
			print "*\n\n*ERR: dude, there are already journal entries made! you can't be switching the fiscal year info now !\n";
			last;
		}	
		
		print "\n\n* Enter 'from month', 'from day', 'to month', 'to day', and 'current fiscal year' (all can be either 1 or 2 digits, year must be 4 digit, and have at least one space between)";
		my $input = <STDIN>;
		chomp($input);
		if($input =~ m/^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d{4})\s*$/)
		{
			my $fm = $1;
			my $fd = $2;
			my $tm = $3;
			my $td = $4;
			my $cfy = $5;
			
			if($tm == 2) { print "* ERR: end month can't be february\n"; next; }
			
			my $daybefore = $fd - 1;
			# one day before the from-day should be equal to to-day
			my $monbefore = $fm;
						
			if($daybefore == 0)
			{
				$monbefore--;
				
				if($monbefore == 0)
				{
					$monbefore = 12;
					$daybefore = 31;
				}
				else
				{
					$daybefore = days_in_mon($cfy, $monbefore);
				}
			}
						
			if(($monbefore != $tm ) or ($daybefore != $td))
			{
				print "\n\n*********************************************** ERR: invalid range of start/end dates, must be a complete year.... CANCELLED\n";
				next;
			}
			my $init_ud = $cfy.'-'.sprintf("%02d", $fm).'-'.sprintf("%02d", $fd);
			
			my $sql = "UPDATE dateinfo SET from_month = $fm, from_day = $fd, to_month = $tm, to_day = $td, usingdate = '$init_ud', current_fiscal_year = $cfy, year_closed = 'N'";
			my $sth = $dbh->prepare($sql);
			
			$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";			
			$sth->finish();
			($fiscal_start, $fiscal_end , $usingdate) = get_fiscal_year_start_end();
		}
		next;
	}

	if($ch eq 'u')
	{
	    if(!fy_set())
	    {
		$msg = "\n\n************************************************* can't move usingdate -- fiscal year not set yet.\n";
		next;
	    }

	    print "\nOk, what do you want for the new default date? (MM/DD/YYYY) ";
	    my $in = <STDIN>;
	    chomp($in);

	    if(invalid_date($in))
	    {
		  $msg = "\n\n******************************** no good boss, '$in' is not in correct format, or is invalid, I'm not changing the date, try again.\n";
		  next;
	    }
	    # between start and end of fiscal year?
	    
	    my $ed_y = '';
	    my $ed_m = '';
	    my $ed_d = '';
	
	    my $sd_y = '';
	    my $sd_m = '';
	    my $sd_d = '';
	
	    my $in_y = '';
	    my $in_m = '';
	    my $in_d = '';
	
	    if($in =~ m!^(\d+)/(\d+)/(\d{4})$!)
	    {
	      $in_y = $3;
	      $in_m = $1;
	      $in_d = $2;
	    }
	
	  if($usingdate =~ m!^(\d{4})-(\d+)-(\d+)$!)
	  {
	      $sd_y = $1;
	      $sd_m = $2;
	      $sd_d = $3;	
	  }
	
	  if($fiscal_end =~ m!^(\d+)/(\d+)/(\d{4})$!)
	  {
	      $ed_y = $3;
	      $ed_m = $1;
	      $ed_d = $2;	
	  }
	
	  my $int_in = ($in_y) * 10000 + $in_m * 100 + $in_d;
	  my $int_sd = ($sd_y) * 10000 + $sd_m * 100 + $sd_d;
	  my $int_ed = ($ed_y) * 10000 + $ed_m * 100 + $ed_d;

	  if($int_in == $int_sd)
	  {
	      $msg = "\n\n************************************************** Using date already is '$in' boss !!\n\n";
	      next;
	  }
	  
	  if($int_in < $int_sd)
	  {
	      $msg = "\n\n**********************************  Can't make the using date earlier than what it already is boss!!\n\n";
	      next;
	  }

	  if($int_in > $int_ed)
	  {
	      $msg = "\n\n********************************* can't make the using date past the last day in fiscal year --- use 'forward books' options for that\n";
	      next;
	  }
	  
	  #print "\n\n\n . . .changing using date. . . to '$int_in' . . . \n";
	  
	  my $sqldate = $in_y.'-'.sprintf("%02d", $in_m).'-'.sprintf("%02d", $in_d);	  
	  my $sql = "UPDATE dateinfo SET usingdate='$sqldate'";	  
	  my $sth = $dbh->prepare($sql);
	  $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	  $sth->finish();
	  
	    ### done changing using date.

	   ($fiscal_start, $fiscal_end , $usingdate) = get_fiscal_year_start_end();
	    next;
	}

	if($ch eq 's')
	{
	    if(there_are_journal_entries())
	    {
		$msg = ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Nice try! you're not allowed adjusting balances now that journal entries are made this fiscal year!\n";
		next;
	    }
	    print "Account: ";
	    my $acc = <STDIN>;
	    chomp($acc); 
	    $acc =~ s/^\s*(\d+)\s*$/$1/;
	    
	    if($acc == $CE_ACC)
	    {
	    	$msg = "\n>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Nope, you aren't allowed to set initial balance of current earnings account!\n";
	    	next;
	    }
	    
	    if(($acc >= 4000) && ($acc <=5999))
	    {
	    	$msg = "\n>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Not allowed to set initial balance of any revenue or expense accounts!\n";
	    	next;
	    }

	    if(!(exists $accounts{$acc}))
	    {
		$msg = "\n>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> account '$acc' doesn't exist.\n";
		next;
	    }

	    print "What is the opening balance for account $acc ? (specify value with 'd' or 'c' suffix (debit balance or credit balance): ";
	    my $amt = <STDIN>;
	    my $orig = $amt;

	    chomp($amt);
	    my $doc;

	    if($amt !~ m/^\s*\d+(?:\.\d*)?\s*([dc])\s*$/)
	    {
		    $msg = "\n\n>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> amount '$amt' is not a valid number (note-- can't be negative, use 'd' or 'c' suffix for debit balance or credit balance).\n";
		    next;
	    }

	    if($amt =~ m/^\s*(.+)\s*[dc]\s*$/)
	    {
		$amt = $1;
		my $err;

		$amt = convert_to_cents($amt, \$err, $mode);

		if($err)
		{
		    $msg = "\n\n************************************************** value '$amt' is invalid.\n";
		    next;
		}
	    }

	    if($orig =~ m/^\s*\d+(?:\.\d*)?\s*([dc])\s*$/)
	    {
		$doc = $1;
	    }

	    if(negative($doc, $acc))
	    {
		  $amt = (-1) * $amt;
	    }

	    my $sql = 'UPDATE chart_of_accounts SET initial_balance = '.$amt.' WHERE number = '.$acc;
	    my $sth = $dbh->prepare($sql);
	    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
	    $sth->finish();
	    $msg = "\n\n * Opening balance of account $acc successfully set.\n";
	}
	elsif($ch eq 'l')
	{
		my $acc = '';
		my $st_dt = '';
		my $en_dt = '';
		my $back = 0;

		if(!there_are_journal_entries())
		{
			next;
		}

		while(1)
		{
			print "\nAccount (or 'b' to go back): ";

			$acc = <STDIN>;
			chomp($acc);

			if($acc eq 'q')
			{
				exit_prog($dbh);
			}

			if($acc eq 'b')
			{
				$back = 1;			
				last;
			}

			if(!(exists $accounts{$acc}))
			{
				print "* account '$acc' doesn't exist.\n";
				next;
			}

			last;
		}

		if($back) { next; }

		while(1)
		{	
			print "Start Date: (just press enter for '$fiscal_start', or 'b' to to back) ";
			$st_dt = <STDIN>;
			chomp($st_dt);
			
			if($st_dt eq '') { $st_dt = $fiscal_start; }
			
			if($st_dt eq 'q') { exit_prog($dbh); }

			if($st_dt eq 'b')
			{
				$back = 1;
				last;
			}

			if(invalid_date($st_dt))
			{
				print "invalid date '$st_dt' (format is MM/DD/YYYY)\n";
				next;
			}	

			last;	
		}

		if($back) { next; }

		while(1)
		{	
			print "End Date: (just press enter for '$fiscal_end', or 'b' to go back) ";
			$en_dt = <STDIN>;
			chomp($en_dt);
			
			if($en_dt eq '') { $en_dt = $fiscal_end; }
			
			if($en_dt eq 'q') { exit_prog($dbh); }

			if($en_dt eq 'b')
			{
				$back = 1;
				last;
			}

			if(invalid_date($en_dt))
			{
				print "invalid date '$en_dt' (format is MM/DD/YYYY)\n";
				next;
			}	

			last;	
		}

		if($back) { next; }

		my $start_date = format_date($st_dt);
	
		my $end_date = format_date($en_dt);
			
		my $sql = "select transaction_date, amount, debiting_or_crediting, je_id, comment from journal_entry_part inner join journal_entries on journal_entry_part.je_id = journal_entries.id where account = $acc and journal_entries.transaction_date >= '$start_date' and journal_entries.transaction_date <= '$end_date' order by je_id asc, transaction_date asc";

		my $init = get_opening_balance($acc);
		my $bal = $init;

		my $sth = $dbh->prepare($sql);

		$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";

		my @row = ();
		my $html = '';

		$html = '<html><head><style type="text/css"> th { font-family:arial; color:#FFFFFF; background-color: #506A9A; font-weight: normal;} h2 { font-family:arial; color: #506A9A; font-weight: bold;} h4 { font-family:arial; color: #506A9A; font-weight: bold;} h1 { font-family:arial; color: #506A9A; font-weight: bold;} h3 { font-family:arial; color: #506A9A; font-weight: bold;} h5 { font-family:arial; color: #506A9A; font-weight: bold;} td { font-family:arial; background-color: #BACCFF; font-weight: normal;} td.number { font-family:arial;; text-align:right; } table.border { #506a9a solid;}
</style></head>';

		$html .= '<body font="arial"><center>';
		$html .= '<h1>Ledger for account '.$acc.': '.$accounts{$acc}."<br></h1><h3><b>For period $st_dt to $en_dt</b></h3>";

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
		$html .= '<tr><th>Date</th><th>JE #</th><th>Comment</th><th>Debit</th><th>Credit</th><th>Debit Balance</th><th>Credit Balance</th></tr>';

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
					$html .= '<tr><td>'.friendlydate($date,"short").'</td>';
					$html .= '<td>'.$jenum.'</td>';
					$html .= '<td>'.$comment.'</td>';
					$html .= '<td align="right">'.c2d($oamt).'</td>';   # debit
					$html .= '<td>&nbsp</td>';       # credit
					$html .= '<td align="right">'.c2d($abs_bal).'</td>';    # debit balance	
					$html .= '<td>&nbsp</td>';       # credit balance
				}
				else
				{
					$html .= '<tr><td>'.friendlydate($date,"short").'</td>';
					$html .= '<td>'.$jenum.'</td>';
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
					$html .= '<tr><td>'.friendlydate($date,"short").'</td>';
					$html .= '<td>'.$jenum.'</td>';
					$html .= '<td>'.$comment.'</td>';
					$html .= '<td>&nbsp</td>';   # debit
					$html .= '<td align="right">'.c2d($oamt).'</td>';       # credit
					$html .= '<td align="right">'.c2d($abs_bal).'</td>';    # debit balance	
					$html .= '<td>&nbsp</td>';       # credit balance
				}
				else
				{
					$html .= '<tr><td>'.friendlydate($date,"short").'</td>';
					$html .= '<td>'.$jenum.'</td>';
					$html .= '<td>'.$comment.'</td>';
					$html .= '<td>&nbsp</td>';   # debit
					$html .= '<td align="right">'.c2d($oamt).'</td>';       # credit
					$html .= '<td>&nbsp</td>';    # debit balance	
					$html .= '<td align="right">'.c2d($abs_bal).'</td>';       # credit balance
				}
			}
		}
		
		$html .= '</table>';
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
		my $cmd = '';

		if($brow =~ m!/$!)
		{
			$cmd = $brow.$temp;
		}
		else
		{
			$cmd = $brow.' '.$temp;
		}
		
		$msg = ">>>>>>>>>>>>>>>>>>>>>>>>>>>>  Open / Refresh browser to file '$temp'\n";	
		#system("$cmd"); 
		next;
	}
	elsif($ch eq 'j')
	{
		my $sql = 'select journal_entries.id, transaction_date, comment, account, debiting_or_crediting, amount from journal_entries inner join journal_entry_part where journal_entries.id = journal_entry_part.je_id order by journal_entries.id asc, debiting_or_crediting desc';
		my $html = '<html><head><style type="text/css"> th { font-family:arial; color:#FFFFFF; background-color: #506A9A; font-weight: normal;} h2 { font-family:arial; color: #506A9A; font-weight: bold;} h4 { font-family:arial; color: #506A9A; font-weight: bold;} h1 { font-family:arial; color: #506A9A; font-weight: bold;} h3 { font-family:arial; color: #506A9A; font-weight: bold;} h5 { font-family:arial; color: #506A9A; font-weight: bold;} td { font-family:arial; background-color: #BACCFF; font-weight: normal;} td.number { font-family:arial;; text-align:right; } table.border { #506a9a solid;}
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
		
				$je_html = '<h4><u>Entry # '.$pje.' on '.$pdate.' "'.$pcomment.'"</u></h4>';
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

		$je_html = '<h4><u>Entry # '.$pje.' on '.$pdate.' "'.$pcomment.'"</u></h4>';
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

		$sth->finish();
		$html .= '</font></center></body></html>';
		
		my $temp = 'je_list.html';

		if(!open(F, ">$temp"))
		{
		    print "\n\n***************************************************** ERR: can't write to file '$temp'\n\n";
		    next;
		}
		
		print F $html;
		close(F);

		my $cmd = '';

		if($brow =~ m!/$!)
		{
			$cmd = $brow.$temp;
		}
		else
		{
			$cmd = $brow.' '.$temp;
		}
	
		$msg = ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> open/refresh browser to file '$temp'\n";	
		#system("$cmd"); 
		next;
	}
	elsif($ch eq 'c')
	{
		my $cancel = 0;
		my $msg = '';
		
		while(1)
		{
			foreach my $i (1..75) { print "\n"; }
			if($msg) { print $msg."\n\n"; }
			
			print "\nL) List all accounts (with opening balances)\n";
			print "\nC) Create a new account\n";
			print "\nE) Edit an account's description and type\n";

			my $candel = 0;

			if(!there_are_journal_entries())
			{
			    print "\nD) Delete an account\n";
			    $candel = 1;
			}

			print "\nB) Go back\n"; 
			print "\nQ) Quit program\n\n";

			print "Enter your choice: ";

			my $ch = <STDIN>;
			chomp($ch);
			$ch =~ tr/A-Z/a-z/;

			if($ch eq 'd')
			{
			    if(!$candel)
			    {
				$msg = ">>>>>>>>>>>>>>>>>>>>>>>>>> You're not allowed to delete! journal entries have been made already this fiscal year.\n";
				next;
			    }

			    print "DELETE: enter account number: "; 
			    my $acc = <STDIN>;
			    chomp($acc);
			    if(!(exists $accounts{$acc}))
			    {
				   $msg = ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> That account doesn't exist anyway - '$acc'\n";
				   next;
			    }
			    
			    if(($acc == $CE_ACC) || ($acc == $RE_ACC))
			    {
			    	$msg = ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Not allowed to delete current earnings or retained earnings account!\n";
			    	next;
			    }
			    
			    my $sql = 'DELETE from chart_of_accounts WHERE number = '.$acc;
			    my $sth = $dbh->prepare($sql);
			    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
			    $sth->finish();
			    print "* * Account '$acc' successfully deleted\n";
			    %accounts = ();
			    %types = ();
			    get_accounts(\%accounts, \%types);
			}
		    
			elsif($ch eq 'l')
			{
			      my $html = '<html><head><style type="text/css"> th { font-family:arial; color:#FFFFFF; background-color: #506A9A; font-weight: normal;} h2 { font-family:arial; color: #506A9A; font-weight: bold;} h4 { font-family:arial; color: #506A9A; font-weight: bold;} h1 { font-family:arial; color: #506A9A; font-weight: bold;} h3 { font-family:arial; color: #506A9A; font-weight: bold;} h5 { font-family:arial; color: #506A9A; font-weight: bold;} td { font-family:arial; background-color: #BACCFF; font-weight: normal;} td.number { font-family:arial;; text-align:right; } table.border { #506a9a solid;}
</style></head><body><table cellpadding="5px"><tr><th>number</th><th>type</th><th>description</th><th>opening balance</th></tr>';
			      my $temp = 'accounts.html';

			      if(-f "$temp")
			      {
				  unlink("$temp");
				  if(-f "$temp")
				  {  
				      $msg = "*ERR: can't delete $temp\n";
				      next;
				  }
			      }
			      if(!open(F,">$temp"))
			      {
				  $msg = "*ERR: can't create $temp\n";
				  next;
			      }
			      my $sql = "SELECT number, type, name, initial_balance FROM chart_of_accounts";
			      my $sth = $dbh->prepare($sql);
			      $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
			      my @row;
			      while(@row = $sth->fetchrow_array)
			      { 
				  $html .= '<tr>';
				  my $col = 0;
				  foreach my $d (@row)
				  {
				      if($col == 3)
				      {
					  $html .= '<td align="right">'.displaybal($d).'</td>';
				      }
				      else
				      {
					  $html .= '<td align="right">'.$d.'</td>';
				      }
				      $col++;
				  }
				  $html .= '</tr>';
			      }
			      $sth->finish();
			      $html .= '</body></html>';
			      print F $html;
			      close(F);
			      my $cmd = '';

			      if($brow =~ m!/$!)
			      {
					$cmd = $brow.$temp;
                              }
			      else
			      {
					$cmd = $brow.' '.$temp;
                              }
			      $msg = ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> open/refresh browser to file '$temp'\n";	
			      #`$cmd`;
			      
			}
			elsif(($ch eq 'c') or ($ch eq 'e'))
			{
				my $cancel = 0;
				my $acc_num = 0;
				my $acc_desc = '';
				my $acc_type = '';

				while(1)
				{
					if($ch eq 'e')
					{
					    print "EDIT: enter 4 digit account number of the existing account, then space, then description - this will overwrite the type and description of the existing account.  For a 'left' account enter an 'L' right after the account number (no space, example '1030L').\n";
					}
					else
					{
					    print "CREATE: Enter a 4 digit account number, space, then account description, *OR* 'c' to cancel (for 'left' account enter L right after account number, example '1030L')\n";
					}
					my $ch = <STDIN>;
					chomp($ch);

					if(($ch eq 'c') or ($ch eq 'C'))
					{
						$cancel = 1;
						last;
					}
					if($ch =~ m/^\s*(\d{4})(.)(.+?)\s*$/)
					{
						$acc_num = $1;
						$acc_type = $2;
						$acc_desc = $3;	
												
						if($acc_type eq ' ') 
						{ 
						    $acc_type = 'R'; 
						}
						elsif($acc_type eq 'l')
						{
						    $acc_type = 'L';
						}
						elsif($acc_type eq 'L')
						{
						    $acc_type = 'L';
						}
						else
						{
						      print "\n\n************************* I didn't understand that.\n\n";
						      next;
						}
					
						if($acc_num eq $CE_ACC)
						{
							print "\n*** >>>>>>>>>>>>>> ERR: $CE_ACC is the current earnings account - you don't have to create it.   I maintain that myself :)\n\n";
							next;
						}
	
						if(($acc_num < 1000) or ($acc_num > 5999))
						{
							print "\n*********************** Invalid account number ($acc_num), must be between 1000 and 5999\n\n";
							next;
						}

						$acc_desc = substr($acc_desc, 0, 80);
						last;
					}
					else
					{
					      print  "\n> > > > >  > > >  I didn't understand that.\n\n";
					      next;
					}
				}
				if(!$cancel)
				{
					# creating new account...
				
					$acc_type =~ tr/a-z/A-Z/;
					$acc_desc =~ s!'!\\\'!g;

					if($ch eq 'c')
					{
					    if($accounts{$acc_num})
					    {
						$msg = "************************************************************** That account ('$acc_num') already exists!\n";
						next;
					    }

					    my $sql = "INSERT INTO chart_of_accounts(number,type,name,initial_balance) VALUES(".$acc_num.",'".$acc_type."','".$acc_desc."',0);";
					    my $sth = $dbh->prepare($sql);
					    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
					    print "\n* * * Account added successfully.\n";
					    $sth->finish();
					    %accounts = ();
					    %types = ();
					    get_accounts(\%accounts, \%types);
					    $msg = "* * * Account $acc_num created.\n";
					}
					else
					{
					    # do NOT allow editing of balance.. that is with the 'S' command from main menu

					    if(!(exists $accounts{$acc_num}))
					    {
						  $msg = ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ERR: that account ($acc_num) doesn't exist ,can't edit, try 'c' to create.";
						  next;
					    }
					    my $sql = "UPDATE chart_of_accounts SET type = '".$acc_type."', name='".$acc_desc."' WHERE number = $acc_num";
					    my $sth = $dbh->prepare($sql);
					    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
					    $sth->finish();
					    run_sql("COMMIT");
					    $msg = "\n* * * Account $acc_num changed.";
					    next;
					}
				}
			}
			elsif($ch eq 'b')
			{
				$cancel = 1;
				last;
			}	
			elsif($ch eq 'q')
			{
				exit_prog($dbh);
			}	
			else
			{
				$msg = "\n>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> you didn't pick one of the choices.\n";
				next;
			}
		}
		
		if($cancel)
		{
			$msg = '';
			next;	
		} 
	}
	elsif($ch eq 'i')
	{
	}
	elsif($ch eq 'b')
	{
	}
	elsif($ch eq 'q')
	{ 
		exit_prog($dbh);
	}
	else
	{
		print "\n>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  I don't know the command '$ch'.\n\n";
	}
}

#exit_prog($dbh);

sub invalid_date
{
	# make sure it is month, day , year, example 5/30/2013 for may 30th 2013.
	my ($date ) = @_;
	
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

sub get_accounts
{
        my ($ref , $ref2) = @_;
        my $sql = "SELECT number, name, type FROM chart_of_accounts";
        my $sth = $dbh->prepare($sql);
        $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";

        my @row = ();

        while(@row = $sth->fetchrow_array)
        {
                $ref->{$row[0]} = $row[1];
		$ref2->{$row[0]} = $row[2];
        }

        $sth->finish();
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

sub acc_is_doc
{
    my ($acc) = @_;

    my $debitacc = 'Credit Balance';
    my $op = 'Debit Balance';

    if(($acc >= 1000) and ($acc <= 1999)) { $debitacc = 'Debit'; $op = 'Credit';}
    if(($acc >= 5000) and ($acc <= 5999)) { $debitacc = 'Debit'; $op = 'Credit'; }

   return ($debitacc, $op);
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

sub get_conf
{
    my $pass='';
    my $brow='';
    my $passmentioned = 0;
    my $mode ='';
    my $db = "";

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
    return ($pass, $brow, $mode,$db);
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

sub fy_set
{
	# fiscal year set?

	my $sql = 'SELECT from_month FROM dateinfo';
	my $sth = $dbh->prepare($sql);
	$sth->execute() or die "SQL error - ".$DBI::errstr."\n";
	my ($from_month) = $sth->fetchrow_array;
	$sth->finish();
	my $set = 0;

	if($from_month != 0)
	{
	    $set = 1;
	}	
	return $set;
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

sub run_sql
{
        my ($qry ) = @_;
        my $sth = $dbh->prepare($qry);
        $sth->execute();
        $sth->finish();
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
		  $assets_html .= '<tr><td width="250px">&nbsp</td><td align="right">-------------------</td><td>&nbsp;</td></tr>';
		  $assets_html .= '<tr><td width="250px">&nbsp</td><td align="right">'.displaybal($subtotal).'</td><td>&nbsp;</td></tr>';
	      }

	      $assets_html .= '<tr><td width="250px">'.$acc.' '.$accounts{$acc}.'</td><td>&nbsp;</td><td align="right">'.$display_balance.'</td></tr>';
	      $subtotal = 0;
	}
	else
	{
	      $subtotal += $val_balance;
	      $assets_html .= '<tr><td width="250px">'.$acc.' '.$accounts{$acc}.'</td><td align="right">'.$display_balance.'</td><td>&nbsp;</td></tr>';
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

	      $liabilities_html .= '<tr><td width="250px">'.$acc.' '.$accounts{$acc}.'</td><td>&nbsp;</td><td align="right">'.$display_balance.'</td></tr>';
	      $subtotal = 0;
	}
	else
	{
	      $subtotal += $val_balance;
	      $liabilities_html .= '<tr><td width="250px">'.$acc.' '.$accounts{$acc}.'</td><td align="right">'.$display_balance.'</td><td>&nbsp;</td></tr>';
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

	      $equity_html .= '<tr><td width="250px">'.$acc.' '.$accounts{$acc}.'</td><td>&nbsp;</td><td align="right">'.$display_balance.'</td></tr>';
	      $subtotal = 0;
	}
	else
	{
	      $subtotal += $val_balance;
	      $equity_html .= '<tr><td width="250px">'.$acc.' '.$accounts{$acc}.'</td><td align="right">'.$display_balance.'</td><td>&nbsp;</td></tr>';
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
    
    my $html = "<html><body><h1>$COMPANY</h1><table border='0'><tr><td valign='top'>$assets_html</td><td valign='top'>$liabilities_html</td></tr><tr><td>&nbsp</td><td valign ='top'>$equity_html</td></tr><tr><td>$total_assets_html</td><td>$total_lande_html</td></tr></table></body></html>";

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

    my $cmd = '';

    if($brow =~ m!/$!)
    {
         $cmd = $brow.$fn;
    }
    else
    {
         $cmd = $brow.' '.$fn;
    }
   $msg = ">>>>>>>>>>>>>>>>>>>>>>>> open/refresh browser to file '$fn'\n";
   #system("$cmd");
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
    $html .= '<html>';
    $html .= '<body>';
    $html .= '<h1>'.$COMPANY.'</h1>';
   
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
	      $income_html .= '<tr><td width="450px">'.$acc.' '.$accounts{$acc}.'</td><td>&nbsp;</td><td align="right">'.$display_balance.'</td></tr>';
	}
	else
	{
	      $income_html .= '<tr><td width="450px">'.$acc.' '.$accounts{$acc}.'</td><td align="right">'.$display_balance.'</td><td>&nbsp;</td></tr>';
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
	      $expense_html .= '<tr><td width="450px">'.$acc.' '.$accounts{$acc}.'</td><td>&nbsp;</td><td align="right">'.$display_balance.'</td></tr>';
	}
	else
	{
	      $expense_html .= '<tr><td width="450px">'.$acc.' '.$accounts{$acc}.'</td><td align="right">'.$display_balance.'</td><td>&nbsp;</td></tr>';
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

    my $cmd = '';

    if($brow =~ m!/$!)
    {
         $cmd = $brow.$fn;
    }
    else
    {
         $cmd = $brow.' '.$fn;
    }
   $msg = ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> open/refresh browser to file '$fn'\n";
   #system("$cmd");
}

sub change_company_name
{
    print "\n\n* OK, what is the company name? ";
    my $cn = <STDIN>;
    chomp($cn);
    $cn =~ s/"/'/g;
    
    my $sql = "update settings set display_name = \"$cn\"";
    my $sth = $dbh->prepare($sql);
    $sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
    $sth->finish();    
    ($COMPANY, $CE_ACC, $RE_ACC) = get_settings();
}




