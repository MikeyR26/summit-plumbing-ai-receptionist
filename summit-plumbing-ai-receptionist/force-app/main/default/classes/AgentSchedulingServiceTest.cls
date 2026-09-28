@isTest
private class AgentSchedulingServiceTest {

    @testSetup
    static void setup() {
        AgentTestDataFactory.setupBaseData();
    }

    @isTest
    static void getSlots_firstCallCreatesDraftAppointment() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        Map<String, Object> result = AgentSchedulingService.getSlots(cust.Id, 'Drain Cleaning', null);
        Test.stopTest();

        System.assertEquals('pending', result.get('status'));
        System.assertNotEquals(null, result.get('serviceAppointmentId'));

        ServiceAppointment sa = [SELECT Id, Status, WorkType.Name FROM ServiceAppointment WHERE Id = :(Id) result.get('serviceAppointmentId')];
        System.assertEquals('None', sa.Status);
        System.assertEquals('Drain Cleaning', sa.WorkType.Name);
    }

    @isTest
    static void getSlots_unknownJobTypeIsRejected() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];
        Boolean threw = false;
        try {
            AgentSchedulingService.getSlots(cust.Id, 'Roof Repair', null);
        } catch (AgentApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('Drain Cleaning'), 'Error should list valid job types');
        }
        System.assert(threw, 'Expected AgentApiException for an unrecognized job type');
    }

    @isTest
    static void getSlots_customerOutsideTerritoryIsRejected() {
        Account acc = new Account(Name = 'Seattle Customer', BillingCity = 'Seattle', BillingState = 'Washington', BillingCountry = 'United States');
        insert acc;
        Contact con = new Contact(AccountId = acc.Id, FirstName = 'Out', LastName = 'OfArea', Phone = '206-555-0000');
        insert con;

        Boolean threw = false;
        try {
            AgentSchedulingService.getSlots(con.Id, 'Drain Cleaning', null);
        } catch (AgentOutsideTerritoryException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AgentOutsideTerritoryException for a customer outside Metro Vancouver');
    }

    @isTest
    static void getSlots_secondCallReturnsSlotsFromScheduler() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];
        Map<String, Object> draft = AgentSchedulingService.getSlots(cust.Id, 'Drain Cleaning', null);
        Id saId = (Id) draft.get('serviceAppointmentId');

        MockFieldServiceScheduler mock = new MockFieldServiceScheduler();
        mock.slotsToReturn = new List<AgentSlot>{
            new AgentSlot(Datetime.newInstanceGmt(2026, 9, 28, 15, 0, 0), Datetime.newInstanceGmt(2026, 9, 28, 16, 0, 0), 90)
        };
        FieldServiceSchedulerFactory.setTestInstance(mock);

        Test.startTest();
        Map<String, Object> result = AgentSchedulingService.getSlots(null, null, saId);
        Test.stopTest();

        System.assertEquals('ready', result.get('status'));
        List<Object> slots = (List<Object>) result.get('slots');
        System.assertEquals(1, slots.size());
        Map<String, Object> slot = (Map<String, Object>) slots[0];
        System.assertEquals('2026-09-28T15:00:00Z', slot.get('startIso'));
    }

    @isTest
    static void getSlots_emptyResultsStillOk() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];
        Map<String, Object> draft = AgentSchedulingService.getSlots(cust.Id, 'Drain Cleaning', null);
        Id saId = (Id) draft.get('serviceAppointmentId');

        FieldServiceSchedulerFactory.setTestInstance(new MockFieldServiceScheduler());

        Test.startTest();
        Map<String, Object> result = AgentSchedulingService.getSlots(null, null, saId);
        Test.stopTest();

        System.assertEquals('ready', result.get('status'));
        System.assertEquals(0, ((List<Object>) result.get('slots')).size());
        System.assertNotEquals(null, result.get('message'));
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
        Map<String, Object> result = AgentSchedulingService.bookAppointment(saId, '2026-09-28T16:00:00Z', '2026-09-28T17:00:00Z');
        Test.stopTest();

        System.assertEquals('Dave Chen', result.get('technician'));
        System.assertNotEquals(null, result.get('confirmationNumber'));
    }

    @isTest
    static void bookAppointment_schedulingFailureIsSurfacedAsError() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];
        Map<String, Object> draft = AgentSchedulingService.getSlots(cust.Id, 'Drain Cleaning', null);
        Id saId = (Id) draft.get('serviceAppointmentId');

        MockFieldServiceScheduler mock = new MockFieldServiceScheduler();
        mock.outcomeToReturn = new FSLScheduleOutcome(false, null, null, null, 'That time is no longer available.');
        FieldServiceSchedulerFactory.setTestInstance(mock);

        Boolean threw = false;
        try {
            AgentSchedulingService.bookAppointment(saId, '2026-09-28T16:00:00Z', '2026-09-28T17:00:00Z');
        } catch (AgentApiException e) {
            threw = true;
            System.assertEquals('That time is no longer available.', e.getMessage());
        }
        System.assert(threw, 'Expected AgentApiException when scheduling fails');
    }

    @isTest
    static void bookAppointment_missingParamsRejected() {
        Boolean threw = false;
        try {
            AgentSchedulingService.bookAppointment(null, null, null);
        } catch (AgentApiException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AgentApiException for missing booking params');
    }

    @isTest
    static void rescheduleAndCancel_fullLifecycle() {
        Contact cust = [SELECT Id FROM Contact LIMIT 1];
        Map<String, Object> draft = AgentSchedulingService.getSlots(cust.Id, 'Leak Repair', null);
        Id saId = (Id) draft.get('serviceAppointmentId');

        MockFieldServiceScheduler mock = new MockFieldServiceScheduler();
        mock.outcomeToReturn = new FSLScheduleOutcome(
            true, 'Maria Santos', Datetime.newInstanceGmt(2026, 9, 28, 16, 0, 0), Datetime.newInstanceGmt(2026, 9, 28, 18, 0, 0), null
        );
        FieldServiceSchedulerFactory.setTestInstance(mock);
        Map<String, Object> booking = AgentSchedulingService.bookAppointment(saId, '2026-09-28T16:00:00Z', '2026-09-28T18:00:00Z');
        String confirmationNumber = (String) booking.get('confirmationNumber');

        // Reschedule: list mode (no new slot chosen yet)
        mock.slotsToReturn = new List<AgentSlot>{
            new AgentSlot(Datetime.newInstanceGmt(2026, 9, 29, 15, 0, 0), Datetime.newInstanceGmt(2026, 9, 29, 17, 0, 0), 80)
        };
        Test.startTest();
        Map<String, Object> listResult = AgentSchedulingService.rescheduleAppointment(confirmationNumber, null, null);
        System.assertEquals('ready', listResult.get('status'));
        System.assertEquals(1, ((List<Object>) listResult.get('slots')).size());

        // Reschedule: commit mode
        mock.outcomeToReturn = new FSLScheduleOutcome(
            true, 'Maria Santos', Datetime.newInstanceGmt(2026, 9, 29, 15, 0, 0), Datetime.newInstanceGmt(2026, 9, 29, 17, 0, 0), null
        );
        Map<String, Object> commitResult = AgentSchedulingService.rescheduleAppointment(confirmationNumber, '2026-09-29T15:00:00Z', '2026-09-29T17:00:00Z');
        System.assertEquals('Maria Santos', commitResult.get('technician'));

        // Cancel
        Map<String, Object> cancelResult = AgentSchedulingService.cancelAppointment(confirmationNumber);
        Test.stopTest();

        System.assertEquals('Canceled', cancelResult.get('status'));
        ServiceAppointment sa = [SELECT Status FROM ServiceAppointment WHERE Id = :saId];
        System.assertEquals('Canceled', sa.Status);
    }

    @isTest
    static void cancelAppointment_unknownConfirmationNumberIsRejected() {
        Boolean threw = false;
        try {
            AgentSchedulingService.cancelAppointment('SA-9999999');
        } catch (AgentApiException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AgentApiException for unknown confirmation number');
    }

    @isTest
    static void cancelAppointment_alreadyCanceledIsRejected() {
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

        AgentSchedulingService.cancelAppointment(confirmationNumber);

        Boolean threw = false;
        try {
            AgentSchedulingService.cancelAppointment(confirmationNumber);
        } catch (AgentApiException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AgentApiException when canceling an already-canceled appointment');
    }
}
