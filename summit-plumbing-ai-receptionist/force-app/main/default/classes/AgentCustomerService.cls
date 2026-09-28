// without sharing: same reasoning as AgentSchedulingService -- backend integration API,
// not a portal user restricted to their own records.
public without sharing class AgentCustomerService {

    public static Map<String, Object> lookupCustomer(String phone, String email) {
        if (String.isBlank(phone) && String.isBlank(email)) {
            throw new AgentApiException('Provide a phone number or email to look up a customer.');
        }

        List<Contact> matches;
        if (String.isNotBlank(phone)) {
            String digitsOnly = phone.replaceAll('[^0-9]', '');
            matches = [
                SELECT Id, AccountId, FirstName, LastName, Phone, Email,
                       Account.BillingStreet, Account.BillingCity, Account.BillingState, Account.BillingPostalCode
                FROM Contact
                WHERE Phone = :phone OR Phone = :digitsOnly
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        } else {
            matches = [
                SELECT Id, AccountId, FirstName, LastName, Phone, Email,
                       Account.BillingStreet, Account.BillingCity, Account.BillingState, Account.BillingPostalCode
                FROM Contact
                WHERE Email = :email
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        }

        if (matches.isEmpty()) {
            return new Map<String, Object>{ 'found' => false };
        }

        Contact c = matches[0];
        return new Map<String, Object>{
            'found' => true,
            'customerId' => c.Id,
            'accountId' => c.AccountId,
            'name' => c.FirstName + ' ' + c.LastName,
            'phone' => c.Phone,
            'email' => c.Email,
            'address' => formatAddress(c.Account.BillingStreet, c.Account.BillingCity, c.Account.BillingState, c.Account.BillingPostalCode)
        };
    }

    public static Map<String, Object> createCustomer(String firstName, String lastName, String phone, String email, String street, String city, String postalCode) {
        if (String.isBlank(firstName) || String.isBlank(lastName)) {
            throw new AgentApiException('First and last name are required.');
        }
        if (String.isBlank(phone) && String.isBlank(email)) {
            throw new AgentApiException('A phone number or email is required.');
        }
        if (String.isBlank(street) || String.isBlank(city)) {
            throw new AgentApiException('A street address and city are required to schedule a visit.');
        }

        String matchedCity = AgentConfig.normalizeCity(city);
        if (!AgentConfig.SUPPORTED_CITIES.contains(matchedCity)) {
            throw new AgentOutsideTerritoryException(
                'We\'re sorry, ' + city + ' is outside our Metro Vancouver service area, so we\'re not able to schedule a visit there.'
            );
        }

        Account acc = new Account(
            Name = firstName + ' ' + lastName,
            Phone = phone,
            BillingStreet = street,
            BillingCity = matchedCity,
            BillingState = 'British Columbia',
            BillingPostalCode = postalCode,
            BillingCountry = 'Canada',
            ShippingStreet = street,
            ShippingCity = matchedCity,
            ShippingState = 'British Columbia',
            ShippingPostalCode = postalCode,
            ShippingCountry = 'Canada'
        );
        Database.insert(acc, AccessLevel.SYSTEM_MODE);

        Contact con = new Contact(
            AccountId = acc.Id,
            FirstName = firstName,
            LastName = lastName,
            Phone = phone,
            Email = email,
            MailingStreet = street,
            MailingCity = matchedCity,
            MailingState = 'British Columbia',
            MailingPostalCode = postalCode,
            MailingCountry = 'Canada'
        );
        Database.insert(con, AccessLevel.SYSTEM_MODE);

        return new Map<String, Object>{
            'customerId' => con.Id,
            'accountId' => acc.Id,
            'name' => firstName + ' ' + lastName,
            'address' => formatAddress(street, matchedCity, 'British Columbia', postalCode)
        };
    }

    public static String formatAddress(String street, String city, String state, String postalCode) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(street)) parts.add(street);
        if (String.isNotBlank(city)) parts.add(city);
        if (String.isNotBlank(state)) parts.add(state);
        if (String.isNotBlank(postalCode)) parts.add(postalCode);
        return String.join(parts, ', ');
    }
}
