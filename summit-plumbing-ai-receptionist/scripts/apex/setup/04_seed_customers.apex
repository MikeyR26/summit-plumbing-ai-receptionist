// Phase 2 setup: ~30 seed customers (Account + Contact + address) across Metro Vancouver.
// Idempotent: skips any customer whose Account.Name already exists.
// Each row: FirstName|LastName|Phone|Email|Street|City|PostalCode

List<String> rows = new List<String>{
    'John|Tanaka|604-555-0101|john.tanaka@example.com|1421 Commercial Dr|Vancouver|V5L 3X9',
    'Sarah|MacDonald|604-555-0102|sarah.macdonald@example.com|2255 W 4th Ave|Vancouver|V6K 1P1',
    'Wei|Zhang|604-555-0103|wei.zhang@example.com|4580 No. 3 Rd|Richmond|V6X 2C3',
    'Priya|Nair|604-555-0104|priya.nair@example.com|8180 Granville Ave|Richmond|V6Y 1P4',
    'Michael|Chow|604-555-0105|michael.chow@example.com|3550 Kingsway|Vancouver|V5R 5L8',
    'Emily|Robertson|604-555-0106|emily.robertson@example.com|615 E Broadway|Vancouver|V5T 1X2',
    'Ahmed|Hassan|604-555-0107|ahmed.hassan@example.com|9350 Cameron St|Burnaby|V3J 7N2',
    'Linda|Fraser|604-555-0108|linda.fraser@example.com|4720 Kingsway|Burnaby|V5H 2A8',
    'David|Kim|604-555-0109|david.kim@example.com|101 Austin Rd|Coquitlam|V3K 3P5',
    'Jessica|Wong|604-555-0110|jessica.wong@example.com|2929 North Rd|Coquitlam|V3B 4P8',
    'Carlos|Reyes|604-555-0111|carlos.reyes@example.com|715 Columbia St|New Westminster|V3M 1B3',
    'Amanda|Singh|604-555-0112|amanda.singh@example.com|1122 6th Ave|New Westminster|V3M 2B5',
    'Ryan|Oliveira|604-555-0113|ryan.oliveira@example.com|1550 Marine Dr|North Vancouver|V7P 1T5',
    'Grace|Lam|604-555-0114|grace.lam@example.com|255 W 15th St|North Vancouver|V7M 1S1',
    'Steven|Bennett|604-555-0115|steven.bennett@example.com|2400 Marine Dr|West Vancouver|V7V 1K9',
    'Natasha|Petrov|604-555-0116|natasha.petrov@example.com|1300 Marine Dr|West Vancouver|V7T 1B7',
    'Brian|Coulson|604-555-0117|brian.coulson@example.com|10355 King George Blvd|Surrey|V3T 2W7',
    'Fatima|Ali|604-555-0118|fatima.ali@example.com|7488 Scott Rd|Surrey|V3W 5M9',
    'Tyler|Anderson|604-555-0119|tyler.anderson@example.com|6084 152 St|Surrey|V3S 3K7',
    'Michelle|Beaulieu|604-555-0120|michelle.beaulieu@example.com|1100 56th St|Delta|V4M 3E8',
    'Jason|Patterson|604-555-0121|jason.patterson@example.com|4837 Delta St|Delta|V4K 2T2',
    'Nicole|Carter|604-555-0122|nicole.carter@example.com|20154 88th Ave|Langley|V1M 2K5',
    'Omar|Farouk|604-555-0123|omar.farouk@example.com|5501 204th St|Langley|V3A 5R2',
    'Hannah|Whitfield|604-555-0124|hannah.whitfield@example.com|301 Main St|Vancouver|V6A 2S6',
    'Marcus|Johansson|604-555-0125|marcus.johansson@example.com|2610 Fraser St|Vancouver|V5T 3W1',
    'Yuki|Sato|604-555-0126|yuki.sato@example.com|4151 Hazelbridge Way|Richmond|V6X 4J7',
    'Diane|Morrison|604-555-0127|diane.morrison@example.com|6540 Bonsor Ave|Burnaby|V5H 3E8',
    'Patrick|OSullivan|604-555-0128|patrick.osullivan@example.com|555 6th St|New Westminster|V3L 3A6',
    'Angela|Foster|604-555-0129|angela.foster@example.com|1200 Lonsdale Ave|North Vancouver|V7M 2H9',
    'Kenji|Watanabe|604-555-0130|kenji.watanabe@example.com|9760 140th St|Surrey|V3T 4M2'
};

Integer created = 0;
Integer skipped = 0;

for (String row : rows) {
    List<String> f = row.split('\\|');
    String firstName = f[0];
    String lastName = f[1];
    String phone = f[2];
    String email = f[3];
    String street = f[4];
    String city = f[5];
    String postalCode = f[6];
    String accountName = firstName + ' ' + lastName;

    List<Account> existing = [SELECT Id FROM Account WHERE Name = :accountName LIMIT 1];
    if (!existing.isEmpty()) {
        skipped++;
        continue;
    }

    Account acc = new Account(
        Name = accountName,
        Phone = phone,
        BillingStreet = street,
        BillingCity = city,
        BillingState = 'British Columbia',
        BillingPostalCode = postalCode,
        BillingCountry = 'Canada',
        ShippingStreet = street,
        ShippingCity = city,
        ShippingState = 'British Columbia',
        ShippingPostalCode = postalCode,
        ShippingCountry = 'Canada'
    );
    insert acc;

    Contact con = new Contact(
        AccountId = acc.Id,
        FirstName = firstName,
        LastName = lastName,
        Phone = phone,
        Email = email,
        MailingStreet = street,
        MailingCity = city,
        MailingState = 'British Columbia',
        MailingPostalCode = postalCode,
        MailingCountry = 'Canada'
    );
    insert con;

    created++;
}

System.debug('=== DONE seeding customers: created=' + created + ' skipped=' + skipped + ' ===');
