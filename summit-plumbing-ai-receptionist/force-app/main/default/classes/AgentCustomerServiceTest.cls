@isTest
private class AgentCustomerServiceTest {

    @testSetup
    static void setup() {
        AgentTestDataFactory.setupBaseData();
    }

    @isTest
    static void lookupCustomer_findsByPhone() {
        Test.startTest();
        Map<String, Object> result = AgentCustomerService.lookupCustomer('604-555-9999', null);
        Test.stopTest();

        System.assertEquals(true, result.get('found'));
        System.assertEquals('Test Customer', result.get('name'));
        System.assertNotEquals(null, result.get('customerId'));
    }

    @isTest
    static void lookupCustomer_findsByEmail() {
        Test.startTest();
        Map<String, Object> result = AgentCustomerService.lookupCustomer(null, 'test.customer@example.com');
        Test.stopTest();

        System.assertEquals(true, result.get('found'));
    }

    @isTest
    static void lookupCustomer_notFound() {
        Test.startTest();
        Map<String, Object> result = AgentCustomerService.lookupCustomer('604-000-0000', null);
        Test.stopTest();

        System.assertEquals(false, result.get('found'));
    }

    @isTest
    static void lookupCustomer_requiresPhoneOrEmail() {
        Boolean threw = false;
        try {
            AgentCustomerService.lookupCustomer(null, null);
        } catch (AgentApiException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AgentApiException when neither phone nor email is provided');
    }

    @isTest
    static void createCustomer_success() {
        Test.startTest();
        Map<String, Object> result = AgentCustomerService.createCustomer(
            'Jane', 'Doe', '604-555-1234', 'jane.doe@example.com', '456 New St', 'Richmond', 'V6X 1A1'
        );
        Test.stopTest();

        System.assertNotEquals(null, result.get('customerId'));
        System.assertNotEquals(null, result.get('accountId'));
        System.assertEquals('Jane Doe', result.get('name'));

        Contact created = [SELECT Id, Account.BillingCity FROM Contact WHERE Id = :(Id) result.get('customerId')];
        System.assertEquals('Richmond', created.Account.BillingCity);
    }

    @isTest
    static void createCustomer_outsideTerritoryIsRejected() {
        Boolean threw = false;
        try {
            AgentCustomerService.createCustomer(
                'John', 'Smith', '206-555-1234', 'john.smith@example.com', '789 Pine St', 'Seattle', '98101'
            );
        } catch (AgentOutsideTerritoryException e) {
            threw = true;
            System.assert(e.getMessage().contains('Seattle'), 'Error message should mention the rejected city');
        }
        System.assert(threw, 'Expected AgentOutsideTerritoryException for an out-of-territory city');
    }

    @isTest
    static void createCustomer_missingNameIsRejected() {
        Boolean threw = false;
        try {
            AgentCustomerService.createCustomer(
                null, null, '604-555-1234', 'x@example.com', '1 Main St', 'Vancouver', 'V5L 1A1'
            );
        } catch (AgentApiException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AgentApiException when name is missing');
    }

    @isTest
    static void createCustomer_missingContactInfoIsRejected() {
        Boolean threw = false;
        try {
            AgentCustomerService.createCustomer(
                'Jane', 'Doe', null, null, '1 Main St', 'Vancouver', 'V5L 1A1'
            );
        } catch (AgentApiException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AgentApiException when neither phone nor email is provided');
    }

    @isTest
    static void createCustomer_missingAddressIsRejected() {
        Boolean threw = false;
        try {
            AgentCustomerService.createCustomer(
                'Jane', 'Doe', '604-555-1234', 'jane.doe@example.com', null, null, null
            );
        } catch (AgentApiException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AgentApiException when address is missing');
    }

    @isTest
    static void createCustomer_cityMatchIsCaseInsensitive() {
        Test.startTest();
        Map<String, Object> result = AgentCustomerService.createCustomer(
            'Jane', 'Doe', '604-555-1234', 'jane.doe@example.com', '456 New St', 'richmond', 'V6X 1A1'
        );
        Test.stopTest();

        Contact created = [SELECT Account.BillingCity FROM Contact WHERE Id = :(Id) result.get('customerId')];
        System.assertEquals('Richmond', created.Account.BillingCity, 'City should be normalized to canonical casing');
    }
}
