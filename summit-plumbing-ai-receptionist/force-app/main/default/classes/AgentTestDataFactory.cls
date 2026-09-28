// Shared minimal test data for Agent API tests. Standard @isTest classes run with
// SeeAllData=false, so org data (Phase 2 seed data) is not visible -- every test class
// needs its own copy of the small set of records AgentConfig looks up by name.
@isTest
public class AgentTestDataFactory {
    public static void setupBaseData() {
        OperatingHours oh = new OperatingHours(Name = 'Test Operating Hours', TimeZone = 'America/Vancouver');
        insert oh;

        ServiceTerritory territory = new ServiceTerritory(
            Name = AgentConfig.SERVICE_TERRITORY_NAME,
            IsActive = true,
            OperatingHoursId = oh.Id
        );
        insert territory;

        List<WorkType> workTypes = new List<WorkType>{
            new WorkType(Name = 'Drain Cleaning', EstimatedDuration = 1, DurationType = 'Hours', TimeframeStart = 0, TimeframeEnd = 14, TimeFrameStartUnit = 'Days', TimeFrameEndUnit = 'Days'),
            new WorkType(Name = 'Water Heater Install', EstimatedDuration = 3, DurationType = 'Hours', TimeframeStart = 0, TimeframeEnd = 14, TimeFrameStartUnit = 'Days', TimeFrameEndUnit = 'Days'),
            new WorkType(Name = 'Leak Repair', EstimatedDuration = 2, DurationType = 'Hours', TimeframeStart = 0, TimeframeEnd = 14, TimeFrameStartUnit = 'Days', TimeFrameEndUnit = 'Days'),
            new WorkType(Name = 'Emergency Call-out', EstimatedDuration = 1.5, DurationType = 'Hours', TimeframeStart = 0, TimeframeEnd = 14, TimeFrameStartUnit = 'Days', TimeFrameEndUnit = 'Days')
        };
        insert workTypes;

        insert new FSL__Scheduling_Policy__c(Name = AgentConfig.SCHEDULING_POLICY_NAME);

        Account acc = new Account(
            Name = 'Test Customer',
            Phone = '604-555-9999',
            BillingStreet = '123 Test St',
            BillingCity = 'Vancouver',
            BillingState = 'British Columbia',
            BillingPostalCode = 'V5L 1A1',
            BillingCountry = 'Canada'
        );
        insert acc;

        Contact con = new Contact(
            AccountId = acc.Id,
            FirstName = 'Test',
            LastName = 'Customer',
            Phone = '604-555-9999',
            Email = 'test.customer@example.com',
            MailingStreet = '123 Test St',
            MailingCity = 'Vancouver',
            MailingState = 'British Columbia',
            MailingPostalCode = 'V5L 1A1',
            MailingCountry = 'Canada'
        );
        insert con;
    }
}
