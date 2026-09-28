// Exercises the @RestResource wrapper classes directly (JSON parsing, delegation to the
// service layer, and exception-to-HTTP-status mapping) via RestContext mocking.
@isTest
private class AgentApiRestTest {

    @testSetup
    static void setup() {
        AgentTestDataFactory.setupBaseData();
    }

    private static Map<String, Object> callResource(String uri, Map<String, Object> body) {
        RestRequest req = new RestRequest();
        req.requestURI = uri;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        if (uri.endsWith('lookupCustomer')) {
            AgentLookupCustomerResource.lookupCustomer();
        } else if (uri.endsWith('createCustomer')) {
            AgentCreateCustomerResource.createCustomer();
        } else if (uri.endsWith('getSlots')) {
            AgentGetSlotsResource.getSlots();
        } else if (uri.endsWith('bookAppointment')) {
            AgentBookAppointmentResource.bookAppointment();
        } else if (uri.endsWith('rescheduleAppointment')) {
            AgentRescheduleAppointmentResource.rescheduleAppointment();
        } else if (uri.endsWith('cancelAppointment')) {
            AgentCancelAppointmentResource.cancelAppointment();
        }

        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    @isTest
    static void lookupCustomer_success() {
        Test.startTest();
        Map<String, Object> resp = callResource('/agent/v1/lookupCustomer', new Map<String, Object>{ 'phone' => '604-555-9999' });
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, resp.get('ok'));
    }

    @isTest
    static void lookupCustomer_badRequestReturns400() {
        Test.startTest();
        Map<String, Object> resp = callResource('/agent/v1/lookupCustomer', new Map<String, Object>());
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, resp.get('ok'));
        System.assertEquals('BAD_REQUEST', resp.get('code'));
    }

    @isTest
    static void createCustomer_success() {
        Test.startTest();
        Map<String, Object> resp = callResource('/agent/v1/createCustomer', new Map<String, Object>{
            'firstName' => 'Jane', 'lastName' => 'Doe', 'phone' => '604-555-1234',
            'email' => 'jane@example.com', 'street' => '1 Main St', 'city' => 'Vancouver', 'postalCode' => 'V5L 1A1'
        });
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, resp.get('ok'));
    }

    @isTest
    static void createCustomer_outsideTerritoryReturns422() {
        Test.startTest();
        Map<String, Object> resp = callResource('/agent/v1/createCustomer', new Map<String, Object>{
            'firstName' => 'John', 'lastName' => 'Smith', 'phone' => '206-555-1234',
            'email' => 'john@example.com', 'street' => '1 Pine St', 'city' => 'Seattle', 'postalCode' => '98101'
        });
        Test.stopTest();

        System.assertEquals(422, RestContext.response.statusCode);
        System.assertEquals('OUTSIDE_TERRITORY', resp.get('code'));
    }

    @isTest
    static void getSlots_pendingThenReady() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        Map<String, Object> pending = callResource('/agent/v1/getSlots', new Map<String, Object>{
            'customerId' => cust.Id, 'jobType' => 'Drain Cleaning'
        });
        System.assertEquals('pending', pending.get('data') != null ? ((Map<String, Object>) pending.get('data')).get('status') : null);

        Id saId = (Id) ((Map<String, Object>) pending.get('data')).get('serviceAppointmentId');

        MockFieldServiceScheduler mock = new MockFieldServiceScheduler();
        mock.slotsToReturn = new List<AgentSlot>{
            new AgentSlot(Datetime.newInstanceGmt(2026, 9, 28, 15, 0, 0), Datetime.newInstanceGmt(2026, 9, 28, 16, 0, 0), 90)
        };
        FieldServiceSchedulerFactory.setTestInstance(mock);

        Map<String, Object> ready = callResource('/agent/v1/getSlots', new Map<String, Object>{ 'serviceAppointmentId' => saId });
        Test.stopTest();

        Map<String, Object> readyData = (Map<String, Object>) ready.get('data');
        System.assertEquals('ready', readyData.get('status'));
        System.assertEquals(1, ((List<Object>) readyData.get('slots')).size());
    }

    @isTest
    static void bookAppointment_success() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];
        Map<String, Object> draft = AgentSchedulingService.getSlots(cust.Id, 'Drain Cleaning', null);
        Id saId = (Id) draft.get('serviceAppointmentId');

        MockFieldServiceScheduler mock = new MockFieldServiceScheduler();
        mock.outcomeToReturn = new FSLScheduleOutcome(
            true, 'Dave Chen', Datetime.newInstanceGmt(2026, 9, 28, 16, 0, 0), Datetime.newInstanceGmt(2026, 9, 28, 17, 0, 0), null
        );
        FieldServiceSchedulerFactory.setTestInstance(mock);

        Test.startTest();
        Map<String, Object> resp = callResource('/agent/v1/bookAppointment', new Map<String, Object>{
            'serviceAppointmentId' => saId, 'slotStartIso' => '2026-09-28T16:00:00Z', 'slotEndIso' => '2026-09-28T17:00:00Z'
        });
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, resp.get('ok'));
    }

    @isTest
    static void rescheduleAppointment_listMode() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];
        Map<String, Object> draft = AgentSchedulingService.getSlots(cust.Id, 'Drain Cleaning', null);
        Id saId = (Id) draft.get('serviceAppointmentId');

        MockFieldServiceScheduler mock = new MockFieldServiceScheduler();
        mock.outcomeToReturn = new FSLScheduleOutcome(
            true, 'Dave Chen', Datetime.newInstanceGmt(2026, 9, 28, 16, 0, 0), Datetime.newInstanceGmt(2026, 9, 28, 17, 0, 0), null
        );
        FieldServiceSchedulerFactory.setTestInstance(mock);
        Map<String, Object> booking = AgentSchedulingService.bookAppointment(saId, '2026-09-28T16:00:00Z', '2026-09-28T17:00:00Z');
        String confirmationNumber = (String) booking.get('confirmationNumber');

        mock.slotsToReturn = new List<AgentSlot>{
            new AgentSlot(Datetime.newInstanceGmt(2026, 9, 29, 15, 0, 0), Datetime.newInstanceGmt(2026, 9, 29, 16, 0, 0), 90)
        };

        Test.startTest();
        Map<String, Object> resp = callResource('/agent/v1/rescheduleAppointment', new Map<String, Object>{
            'confirmationNumber' => confirmationNumber
        });
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> data = (Map<String, Object>) resp.get('data');
        System.assertEquals('ready', data.get('status'));
    }

    @isTest
    static void cancelAppointment_success() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];
        Map<String, Object> draft = AgentSchedulingService.getSlots(cust.Id, 'Drain Cleaning', null);
        Id saId = (Id) draft.get('serviceAppointmentId');

        MockFieldServiceScheduler mock = new MockFieldServiceScheduler();
        mock.outcomeToReturn = new FSLScheduleOutcome(
            true, 'Dave Chen', Datetime.newInstanceGmt(2026, 9, 28, 16, 0, 0), Datetime.newInstanceGmt(2026, 9, 28, 17, 0, 0), null
        );
        FieldServiceSchedulerFactory.setTestInstance(mock);
        Map<String, Object> booking = AgentSchedulingService.bookAppointment(saId, '2026-09-28T16:00:00Z', '2026-09-28T17:00:00Z');
        String confirmationNumber = (String) booking.get('confirmationNumber');

        Test.startTest();
        Map<String, Object> resp = callResource('/agent/v1/cancelAppointment', new Map<String, Object>{
            'confirmationNumber' => confirmationNumber
        });
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> data = (Map<String, Object>) resp.get('data');
        System.assertEquals('Canceled', data.get('status'));
    }

    @isTest
    static void cancelAppointment_unknownConfirmationReturns400() {
        Test.startTest();
        Map<String, Object> resp = callResource('/agent/v1/cancelAppointment', new Map<String, Object>{
            'confirmationNumber' => 'SA-9999999'
        });
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, resp.get('ok'));
    }
}
