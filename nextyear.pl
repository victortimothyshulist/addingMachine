#!/usr/bin/perl
use strict;
use DBI;

my $PATH_TO_MYSQL_CMD = "c:\\Program Files\\MySQL\\MySQL Server 8.0\\bin\\mysql";

my $acc_list = "";
my $dbh;

sub doit
{
    my ($acc, $openingbalance) = @_;
    my $name = $acc->[2];
    $name =~ s/'/\\'/g;
    if ($acc_list ne "") { $acc_list .= ","; }
    $acc_list .= "(".$acc->[0].",'".$acc->[1]."','".$name."',$openingbalance)";       
}

sub get_dateinfo
{
	my $sql = 'SELECT from_month, from_day, to_month, to_day, usingdate, current_fiscal_year FROM dateinfo';
	my $sth = $dbh->prepare($sql);

	$sth->execute() or die "SQL error - ".$DBI::errstr."\n";
	my ($from_month, $from_day, $to_month, $to_day, $usingdate, $current_fiscal_year) = $sth->fetchrow_array;
	$sth->finish();
	
	return($from_month, $from_day, $to_month, $to_day, $usingdate, $current_fiscal_year);
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

my $SQL_TEMPLATE = <<'END_OF_SQL_TEMPLATE';
CREATE DATABASE {__NEW_DB_NAME__};
USE {__NEW_DB_NAME__};

CREATE TABLE chart_of_accounts(
  number int NOT NULL,
  type char(1) NOT NULL,
  name char(80) NOT NULL,
  initial_balance bigint NOT NULL DEFAULT '0',
  UNIQUE KEY number (number)
);

CREATE TABLE dateinfo (
  from_month int NOT NULL,
  from_day int NOT NULL,
  to_month int NOT NULL,
  to_day int NOT NULL,
  usingdate date NOT NULL,
  current_fiscal_year int NOT NULL,
  year_closed char(1) DEFAULT 'N'
);

CREATE TABLE journal_entries (
  id int NOT NULL AUTO_INCREMENT,
  transaction_date date NOT NULL,
  comment char(80) NOT NULL,
  PRIMARY KEY (id)
);

CREATE TABLE journal_entry_part (
  id int NOT NULL AUTO_INCREMENT,
  je_id int NOT NULL,
  account int NOT NULL,
  debiting_or_crediting char(1) DEFAULT NULL,
  amount bigint DEFAULT NULL,
  PRIMARY KEY (id)
);

CREATE TABLE settings (
  display_name char(120) DEFAULT NULL,
  current_earnings_account int DEFAULT NULL,
  retained_earnings_account int DEFAULT NULL
);

INSERT INTO settings VALUES ('{__BIZ_NAME__}',{__CE__},{__RE__});
INSERT INTO dateinfo VALUES (3,1,2,28,'{__DAY_1__}',{__NEXT_YEAR__},'N');
INSERT INTO chart_of_accounts VALUES {__CHART_LIST__};
END_OF_SQL_TEMPLATE

my ($pass, $brow, $mode, $db) = get_conf();

$dbh = DBI->connect("DBI:mysql:$db", 'root', $pass) || die "Could not connect to database: $DBI::errstr";
my $sql = "SELECT number, type, name, initial_balance FROM chart_of_accounts";
my $sth = $dbh->prepare($sql);
$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";
$acc_list = "";

my %acc_info;
my @row;
while(@row = $sth->fetchrow_array)
{ 
    my $type = "";
    if ($row[0] < 2000) {  $type = "ASSET"; }
    elsif($row[0] >= 2000  && $row[0] < 3000) { $type = "LIABILITY" ;}
    elsif($row[0] >= 3000  && $row[0] < 4000) { $type = "EQUITY" ;}
    elsif($row[0] >= 4000  && $row[0] < 5000) { $type = "REVENUE" ;}
    elsif($row[0] >= 5000) { $type = "EXPENSE" ;}

    #print $row[0]."  is a ".$type."\n";
    push @{$acc_info{$type}},   [  $row[0], $row[1], $row[2], $row[3]  ]
}
$sth->finish();

my %current_balance = ();
get_bals(\%current_balance);

my $NET_INCOME = 0;
foreach my $acc (@{$acc_info{'REVENUE'}})
{
    doit($acc, "0") ;
    $NET_INCOME += $current_balance{$acc->[0]}[0];
}

foreach my $acc (@{$acc_info{'EXPENSE'}})
{
        doit($acc, 0);
        $NET_INCOME -= $current_balance{$acc->[0]}[0];
}

foreach my $acc (@{$acc_info{'ASSET'}})
{
       my $ob = $current_balance{$acc->[0]};        
       doit($acc, $ob->[0]);
}

foreach my $acc (@{$acc_info{'LIABILITY'}})
{
       my $ob = $current_balance{$acc->[0]};        
       doit($acc, $ob->[0]);
}

my ($COMPANY, $CE_ACC, $ACCOUNT_FOR_RETAINED_EARNINGS) = get_settings();

my $set_re = 0;
foreach my $acc (@{$acc_info{'EQUITY'}})
{
      my $ob = $current_balance{$acc->[0]};       

      if ($acc->[0] eq $ACCOUNT_FOR_RETAINED_EARNINGS)
      {
              $ob->[0] += $NET_INCOME;
              $set_re = 1;
      }
       doit($acc, $ob->[0]);
}

if($set_re == 0)
{
	print "Dude ! I didn't see the retained earnings account ! ($ACCOUNT_FOR_RETAINED_EARNINGS).  Do something ! lol\n";
	exit(0);
}

my $SQL_CREATE = $SQL_TEMPLATE;
$SQL_CREATE =~ s/{__CHART_LIST__}/$acc_list/;

my $new_db_name = $db;

if ($db =~ m/^.*(\d{4}).*$/)
{
     my $ly = $1;
	 my $ny = $ly + 1;
	 $new_db_name =~ s/$ly/$ny/;    
}
else
{
    print "\n*Cannot find the 4 digit year in the database name of '$db'\n";
	exit;
}

my ($from_month, $from_day, $to_month, $to_day, $usingdate, $current_fiscal_year) = get_dateinfo();

if($usingdate =~ m/.*(\d{4}).*/)
{
    my $y = $1;
	my $ny = $y + 1;
	$usingdate =~ s/$y/$ny/;
}
else
{
	print("\n*ERR: Cannot find the 4 digit year in usingdate (which is '$usingdate' - no 4 digit year in that!)\n");
	exit(1);
}

if($current_fiscal_year =~ m/.*(\d{4}).*/)
{
    my $y = $1;
	my $ny = $y + 1;
	$current_fiscal_year =~ s/$y/$ny/;
}
else
{
	print("\n*ERR: Cannot find the 4 digit year in current_fiscal_year (which is '$current_fiscal_year' - no 4 digit year in that!)\n");
	exit(1);
}

$SQL_CREATE =~ s/{__NEW_DB_NAME__}/$new_db_name/g;
$SQL_CREATE =~ s/{__BIZ_NAME__}/$COMPANY/g;
$SQL_CREATE =~ s/{__CE__}/$CE_ACC/g;
$SQL_CREATE =~ s/{__RE__}/$ACCOUNT_FOR_RETAINED_EARNINGS/g;
$SQL_CREATE =~ s/{__NEXT_YEAR__}/$current_fiscal_year/;

$from_month = sprintf("%02d", $from_month);
$from_day = sprintf("%02d", $from_day);

my $new_ud = $current_fiscal_year."-".$from_month.'-'.$from_day;

$SQL_CREATE =~ s/{__DAY_1__}/$new_ud/;

my $sql_fn = $new_db_name.".sql";
if(!open(FH, ">$sql_fn"))
{
    print "\n*ERR: can't write to file $sql_fn";
	exit;
}

print FH $SQL_CREATE."\n";
close(FH);

# close previous year....
my $sql = "UPDATE dateinfo SET year_closed='Y'";
my $sth = $dbh->prepare($sql);
$sth->execute() or die "SQL error ->> ".$DBI::errstr."\n";

print "\nDone! New year database created $sql_fn, and old year marked as closed in dateinfo table.\n";

my $NEW_DB_CMD_LINE =  '"'.$PATH_TO_MYSQL_CMD.'" -u root -p'.$pass.' < '.$sql_fn;

print("\nAttempting to execute:\n");
print("\t$NEW_DB_CMD_LINE");
print("\n");
`$NEW_DB_CMD_LINE`;

# Re-write the am.conf file to point to the new database !!! :)
my $am_fn = "am.conf";
if(!open(FHC,"<$am_fn"))
{
	print("\n*ERR: can't open $am_fn !! \n");
	exit(1);
}
my @theconfig = ();
foreach my $cline (<FHC>)
{
	   chomp($cline);
	   if($cline =~ m/^\s*database\s*=\s*(.+?)\s*$/)
	   {
		    push @theconfig, "database = ".$new_db_name;
	   }
	   else
	   {
	        push @theconfig, $cline;
	   }
}
close(FHC);

if(!open(FHC,">$am_fn"))
{
	print("\n*ERR: can't write to file $am_fn");
	exit(1);
}

foreach my $cline (@theconfig)
{
	print FHC $cline."\n";
}
close(FHC);

sub acc_is_debit
{
    my ($acc) = @_;

    if(($acc >= 1000) and ($acc <= 1999)) { return 1; }

    if(($acc >= 5000) and ($acc <= 5999)) { return 1; }

    return 0;
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
			$ref->{$acc} = [ $ob{$acc}, ($ob{$acc}) ]; 			
		}
		elsif($ob{$acc} < 0)
		{
			$ref->{$acc} = [ $ob{$acc}, '('.((-1) * $ob{$acc}).')' ]; 					
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
				$ref->{$acc} = [$diff, ($diff) ];
			}
			else
			{
				$ref->{$acc} = [ (-1) * $diff, '('.($diff).')' ];
			}
		}
		elsif($c > $d)
		{
			my $diff = $c - $d;
			
			if(acc_is_debit($acc))
			{
				$ref->{$acc} = [ (-1) * $diff, '('.($diff).')' ];
			}
			else
			{
				$ref->{$acc} = [$diff, ($diff) ];
			}
		}
		else
		{
			$ref->{$acc} = [ 0, '0.00' ]; 
		}
	}
}
