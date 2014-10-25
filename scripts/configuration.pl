=head1 NAME

LedgerSMB::Scripts::configuration - Configuration Workflows for LedgerSMB

=head1 SYNPOPSIS

LedgerSMB::Scripts::configuration->can('action')->($request);

=cut
package LedgerSMB::Scripts::configuration;
use LedgerSMB::Setting;
use LedgerSMB::Setting::Sequence;
use LedgerSMB::AM; # To be removed, only for template directories right now
use strict;
use warnings;

my $locale = $LedgerSMB::App_State::Locale;

our @default_settings = (
   { title => $locale->text('Company Information'),
     items => [
       { name => 'company_name', label => $locale->text('Company Name') },
       { name => 'company_address', 
         type => 'TEXTAREA',
        label => $locale->text('Company Address') },
       { name => 'company_phone', label => $locale->text('Company Phone') },
       { name => 'company_fax', label => $locale->text('Company Fax') },
       { name => 'businessnumber', label => $locale->text('Business Number') },
       { name => 'default_email_to', 
        label => $locale->text('Default Email To') },
       { name => 'default_email_cc', 
        label => $locale->text('Default Email CC') },
       { name => 'default_email_bcc', 
        label => $locale->text('Default Email BCC') },
       { name => 'default_email_from', 
        label => $locale->text('Default Email From') },
       { name => 'company_sales_tax_id', 
        label =>  $locale->text('Company Sales Tax ID') },
       { name => 'company_license_number',
        label =>  $locale->text('Company License Number') },
       { name => 'curr', 
        label => $locale->text('Currencies (colon-separated)')},
       { name => 'weightunit', label => $locale->text('Weight Unit') },
       { name => 'default_country',
        label => $locale->text('Default Country'),
         type => 'SELECT_ONE', },
       { name => 'default_language',
        label => $locale->text('Default Language'),
         type => 'SELECT_ONE', },
       { name => 'templates',
         type => 'SELECT_ONE',
        label => $locale->text('Template Set'), },
       { name => 'format',
         type => 'SELECT_ONE',
        label => $locale->text('Default Format'), },
     ] },
   { title => $locale->text('Security Settings'),
     items => [
       { name => 'password_duration',
        label => $locale->text('Password Duration') },
       { name => 'session_timeout',
        label => $locale->text('Session Timeout'), },
       { name => 'auto_logout',
        label => $locale->text('Automatically Logout'),
         type => 'YES_NO', },
       { name => 'separate_duties',
        label => $locale->text('Separate Duties'),
         type => 'YES_NO', },
       { name => 'lock_description',
        label => 'Lock Item Description',
         type => 'YES_NO', },
     ] },
 { title => $locale->text('Default Accounts'),
   items => [
       { name => 'inventory_accno_id',
         type => 'SELECT_ONE',
        label => $locale->text('Inventory'), },
       { name => 'income_accno_id',
         type => 'SELECT_ONE',
        label => $locale->text('Income'), },
       { name => 'expense_accno_id',
         type => 'SELECT_ONE',
        label => $locale->text('Cost of Goods Sold'), },
       { name => 'fxgain_accno_id',
         type => 'SELECT_ONE',
        label => $locale->text('Foreign Exchange Gain') },
       { name => 'fxloss_accno_id',
         type => 'SELECT_ONE',
        label => $locale->text('Foreign Exchange Loss') },
   ] },
 { title => $locale->text('Next in Sequence'),
   items => [
     { name => 'glnumber', label => $locale->text('GL Reference Number') },
     { name => 'sinumber', 
      label => $locale->text('Sales Invoice/AR Transaction Number'), },
     { name => 'sonumber', label => $locale->text('Sales Order Number') },
     { name => 'sqnumber', label => $locale->text('Sales Quotation Number') },
     { name => 'vinumber' , 
      label => $locale->text('Vendor Invoice/AP Transaction Number')},
     { name => 'ponumber', label => $locale->text('Purchase Order Number') },
     { name => 'rfqnumber', label => $locale->text('RFQ Number') },
     { name => 'partnumber', label => $locale->text('Part Number') },
     { name => 'projectnumber', label => $locale->text('Business Unit Number') },
     { name => 'employeenumber', label => $locale->text('Employee Number') },
     { name => 'customernumber', label => $locale->text('Customer Number') },
     { name => 'vendornumber', label => $locale->text('Vendor Number') },
   ] },
   { title => $locale->text('Misc Settings'),
     items => [  
       { name => 'dojo_theme',
         type => 'SELECT_ONE',
        label => $locale->text('Widgit Themes') },
       { name => 'check_prefix', label => $locale->text('Check Prefix') },
     { name => 'vclimit', label => $locale->text('Max per dropdown') },
       { name => 'check_max_invoices',
        label =>  $locale->text('Max Invoices per Check Stub') },
       { name => 'decimal_places',
        label =>  $locale->text('Decimal Places for Money') },
       { name => 'template_immages',
        label => $locale->text('Images in Templates'),
         type => 'YES_NO', },
     ] },
);

=head1 METHODS/ACTIONS

=over

=item defaults_screen

Shows the defaults screen

=cut

sub defaults_screen{
    my ($request) = @_;
    my $setting_handle = LedgerSMB::Setting->new({base => $request});
    my @defaults;
    for my $dg (@default_settings){
        for my $tb (@{$dg->{items}}){
            push @defaults, $tb->{name};
        }
    }
    for my $skey (@defaults){
        $request->{$skey} = $setting_handle->get($skey);
    }
    my @country_list = $request->call_procedure(
                     procname => 'location_list_country'
    );
    unshift @country_list, {}
        if ! defined $request->{default_country};

    my @language_code_list =
             $request->call_procedure(procname=> 'person__list_languages');
    unshift @language_code_list, {}
        if ! defined $request->{default_language};

    my $expense_accounts = $setting_handle->accounts_by_link('IC_expense');
    my $income_accounts = $setting_handle->accounts_by_link('IC_income');
    my $fx_loss_accounts = $setting_handle->accounts_by_link('FX_loss');
    my $fx_gain_accounts = $setting_handle->accounts_by_link('FX_gain');
    my $inventory_accounts = $setting_handle->accounts_by_link('IC');

    unshift @$expense_accounts, {}
        if ! defined $request->{expense_accno_id};
    unshift @$income_accounts, {}
        if ! defined $request->{income_accno_id};
    unshift @$fx_loss_accounts, {}
        if ! defined $request->{fxloss_accno_id};
    unshift @$fx_gain_accounts, {}
        if ! defined $request->{fxgain_accno_id};
    unshift @$inventory_accounts, {}
        if ! defined $request->{inventory_accno_id};

    my %selects = (
        'dojo_theme'  =>     {name => 'dojo_theme', # TODO autodetect
                           options => [{text => 'Claro', value => 'claro'},
                                       {text => 'Nihilo', value => 'nihilo'},
                                       {text => 'Soria', value => 'soria'},
                                       {text => 'Tundra', value => 'tundra'},],
                   default_values  => [$request->{dojo_theme}]},
        'fxloss_accno_id' => {name => 'fxloss_accno_id',
                           options => $fx_loss_accounts,
                         text_attr => 'text',
                        value_attr => 'id'},
        'fxgain_accno_id' => {name => 'fxgain_accno_id',
                         text_attr => 'text',
                           options => $fx_gain_accounts,
                        value_attr => 'id'},
        'expense_accno_id' => {name => 'expense_accno_id',
                            options =>  $expense_accounts,
                         text_attr => 'text',
                        value_attr => 'id'},
        'income_accno_id' => {name => 'income_accno_id',
                           options => $income_accounts,
                         text_attr => 'text',
                        value_attr => 'id'},
        'inventory_accno_id' => {name => 'inventory_accno_id',
                     options => $inventory_accounts,
                   text_attr => 'text',
                  value_attr => 'id'},
	'default_country' => {name   => 'default_country',
			     options => \@country_list,
			     default_values => [$request->{'default_country'}],
			     text_attr => 'name',
			     value_attr => 'id',
		},
	'default_language' => {name   => 'default_language',
			     options => \@language_code_list,
			     default_values => [$request->{'default_language'}],
			     text_attr => 'description',
			     value_attr => 'code',
		},
	'templates'        => {name => 'templates',
                           options => _get_template_directories(),
                         text_attr => 'text',
                    default_values => [$request->{'templates'}],
                        value_attr => 'value'
               },
        'format'           => {name => 'format',
                           text_attr => 'text',
                          value_attr => 'value',
                      default_values => [$request->{'format'}],
                             options => [{ text => 'HTML',
                                          value => 'html'},
                                         { text => 'PDF',
                                          value => 'pdf'},
                                         { text => 'Postscript',
                                          value => 'postscript'}]
               }
        );
    my $template = LedgerSMB::Template->new_UI(
        user => $LedgerSMB::App_State::User, 
        locale => $locale,
        template => 'Configuration/settings');
    $template->render({
        form => $request,
	# hiddens => \%hiddens,
	selects => \%selects,
        default_settings => \@default_settings,
    });
}

=item sequence_screen

No inputs expected or used

=cut

sub sequence_screen {
    my ($request) = @_;
    eval { @{$request->{sequence_list}} = LedgerSMB::Setting::Sequence->list(); };
    for my $subset (@default_settings){
        $request->{setting_keys} = $subset->{items} 
             if $subset->{title} eq $locale->text('Next in Sequence');
    }
    my $count = 0;
    for my $item (@{$request->{setting_keys}}){
        for my $blacklist (qw(customernumber vendornumber employeenumber)){
            delete $request->{setting_keys}->[$count] if $item->{name} eq $blacklist;
        }
    ++$count;
    }
    LedgerSMB::Template->new_UI(
        user => $LedgerSMB::App_State::User, 
        locale => $locale,
        template => 'Configuration/sequence')->render($request);
      
}

=item save_defaults

Saves settings from the defaults screen

=cut

sub save_defaults {
    my ($request) = @_;
    if (!$request->is_allowed_role(
        {allowed_roles => ['system_settings_change'] })
    ){
       die $locale->text('Access Denied');
    }
    my $setting_handle = LedgerSMB::Setting->new({base => $request});
    my @defaults;
    for my $dg (@default_settings){
        for my $tb (@{$dg->{items}}){
            push @defaults, $tb->{name};
        }
    }
    for my $skey (@defaults){
        $request->{$skey} =~ s/--.*$// if $skey =~ /accno_id/;
        $setting_handle->set($skey, $request->{$skey});
    }
    defaults_screen($request);
}

=item _get_template_directories

Returns set of template directories available.

=cut

sub _get_template_directories {
    my $subdircount = 0;
    my @dirarray;
    opendir ( DIR, $LedgerSMB::Sysconfig::templates) || die $locale->text("Error while opening directory: [_1]",  "./".$LedgerSMB::Sysconfig::templates);
    while( my $name = readdir(DIR)){
        next if ($name =~ /\./);
        if (-d $LedgerSMB::Sysconfig::templates.'/'.$name) {
            push @dirarray, {text => $name, value => $name};
        }
    }
    closedir(DIR);
    return \@dirarray;
}

sub save_sequences {
    my ($request) = @_;
    eval {
    for my $count (1 .. $request->{count}){
	if ($request->{"save_$count"} and $request->{"label_$count"}){
           my %shash;
           for my $key (qw(accept_input setting_key label prefix sequence suffix)){
              $shash{$key} = $request->{"${key}_$count"};
           }
           my $sequence = LedgerSMB::Setting::Sequence->new(%shash);
           $sequence->save; 
        }
    }
    1;
    } or $request->error($@);
    $request->{dbh}->commit;
    sequence_screen($request);
}

=back

=head1 COPYRIGHT

Copyright (C) 2012 The LedgerSMB Core Team.  This file may be reused under the
conditions of the GNU GPL v2 or at your option any later version.  Please see
the accompanying LICENSE.TXT for more information.

=cut

1;
