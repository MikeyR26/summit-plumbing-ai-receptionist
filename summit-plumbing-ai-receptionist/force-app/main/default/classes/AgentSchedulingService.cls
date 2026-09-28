// Orchestrates booking against the FSL scheduling engine via IFieldServiceScheduler.
//
// getSlots() is necessarily a two-call flow: FSL.AppointmentBookingService.getSlots performs
// a real callout, which can't happen in the same transaction as the DML that creates the
// draft WorkOrder/ServiceAppointment (see FSLFieldServiceScheduler). So the first call (no
// serviceAppointmentId) creates the draft and returns status "pending"; the caller calls
// getSlots again with that serviceAppointmentId to get status "ready" with real slots.
public with sharing class AgentSchedulingService {

    public static Map<String, Object> getSlots(Id customerId, String jobType, Id serviceAppointmentId) {
        if (serviceAppointmentId != null) {
            return fetchSlotsForExistingAppointment(serviceAppointmentId);
        }
        return createDraftAppointment(customerId, jobType);
    }

    private static Map<String, Object> createDraftAppointment(Id customerId, String jobType) {
        if (customerId == null) {
            throw new AgentApiException('customerId is required.');
        }
        Map<String, Id> workTypeIds = AgentConfig.getWorkTypeIdsByName();
        if (String.isBlank(jobType) || !workTypeIds.containsKey(jobType)) {
            throw new AgentApiException('Unknown job type "' + jobType + '". Valid options: ' + String.join(new List<String>(workTypeIds.keySet()), ', '));
        }

        List<Contact> customers = [
            SELECT Id, AccountId, Account.BillingStreet, Account.BillingCity, Account.BillingState,
                   Account.BillingPostalCode, Account.BillingCountry, Account.BillingLatitude, Account.BillingLongitude
            FROM Contact
            WHERE Id = :customerId
            LIMIT 1
        ];
        if (customers.isEmpty()) {
            throw new AgentApiException('Customer not found.');
        }
        Contact cust = customers[0];

        String custCity = AgentConfig.normalizeCity(cust.Account.BillingCity);
        if (!AgentConfig.SUPPORTED_CITIES.contains(custCity)) {
            throw new AgentOutsideTerritoryException(
                'This customer\'s address (' + cust.Account.BillingCity + ') is outside our Metro Vancouver service area.'
            );
        }

        Id territoryId = AgentConfig.getServiceTerritoryId();
        Id workTypeId = workTypeIds.get(jobType);

        WorkOrder wo = new WorkOrder(
            Subject = jobType + ' - ' + cust.Id,
            AccountId = cust.AccountId,
            ContactId = cust.Id,
            WorkTypeId = workTypeId,
            ServiceTerritoryId = territoryId,
            Status = 'New',
            Street = cust.Account.BillingStreet,
            City = cust.Account.BillingCity,
            State = cust.Account.BillingState,
            PostalCode = cust.Account.BillingPostalCode,
            Country = cust.Account.BillingCountry,
            Latitude = cust.Account.BillingLatitude,
            Longitude = cust.Account.BillingLongitude
        );
        insert wo;

        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId = wo.Id,
            WorkTypeId = workTypeId,
            ServiceTerritoryId = territoryId,
            Status = 'None',
            Street = cust.Account.BillingStreet,
            City = cust.Account.BillingCity,
            State = cust.Account.BillingState,
            PostalCode = cust.Account.BillingPostalCode,
            Country = cust.Account.BillingCountry,
            Latitude = cust.Account.BillingLatitude,
            Longitude = cust.Account.BillingLongitude
        );
        insert sa;

        return new Map<String, Object>{
            'status' => 'pending',
            'serviceAppointmentId' => sa.Id,
            'message' => 'Call getSlots again with this serviceAppointmentId to retrieve availability.'
        };
    }

    private static Map<String, Object> fetchSlotsForExistingAppointment(Id serviceAppointmentId) {
        List<ServiceAppointment> existing = [SELECT Id FROM ServiceAppointment WHERE Id = :serviceAppointmentId LIMIT 1];
        if (existing.isEmpty()) {
            throw new AgentApiException('Unknown serviceAppointmentId.');
        }

        List<AgentSlot> slots = FieldServiceSchedulerFactory.getInstance().getAvailableSlots(
            serviceAppointmentId, AgentConfig.getSchedulingPolicyId()
        );

        List<Map<String, Object>> slotList = new List<Map<String, Object>>();
        for (AgentSlot s : slots) {
            slotList.add(new Map<String, Object>{
                'start' => AgentDateUtil.toPacificHuman(s.startTime),
                'end' => AgentDateUtil.toPacificHuman(s.finishTime),
                'startIso' => AgentDateUtil.toIso(s.startTime),
                'endIso' => AgentDateUtil.toIso(s.finishTime)
            });
        }

        Map<String, Object> result = new Map<String, Object>{
            'status' => 'ready',
            'serviceAppointmentId' => serviceAppointmentId,
            'slots' => slotList
        };
        if (slotList.isEmpty()) {
            result.put('message', 'No available appointment times in the next two weeks. This may need a human follow-up.');
        }
        return result;
    }

    public static Map<String, Object> bookAppointment(Id serviceAppointmentId, String slotStartIso, String slotEndIso) {
        if (serviceAppointmentId == null || String.isBlank(slotStartIso) || String.isBlank(slotEndIso)) {
            throw new AgentApiException('serviceAppointmentId, slotStartIso, and slotEndIso are required.');
        }
        Datetime windowStart = AgentDateUtil.parseIso(slotStartIso);
        Datetime windowEnd = AgentDateUtil.parseIso(slotEndIso);

        FSLScheduleOutcome outcome = FieldServiceSchedulerFactory.getInstance().scheduleAppointment(
            serviceAppointmentId, AgentConfig.getSchedulingPolicyId(), windowStart, windowEnd
        );

        if (!outcome.success) {
            throw new AgentApiException(outcome.errorMessage);
        }

        List<ServiceAppointment> saList = [SELECT Id, AppointmentNumber FROM ServiceAppointment WHERE Id = :serviceAppointmentId LIMIT 1];
        String confirmationNumber = saList.isEmpty() ? null : saList[0].AppointmentNumber;

        return new Map<String, Object>{
            'confirmationNumber' => confirmationNumber,
            'technician' => outcome.resourceName,
            'start' => AgentDateUtil.toPacificHuman(outcome.schedStart),
            'end' => AgentDateUtil.toPacificHuman(outcome.schedEnd)
        };
    }

    public static Map<String, Object> rescheduleAppointment(String confirmationNumber, String slotStartIso, String slotEndIso) {
        ServiceAppointment sa = findByConfirmationNumber(confirmationNumber);

        if (String.isBlank(slotStartIso) || String.isBlank(slotEndIso)) {
            // List mode: the appointment already exists and is committed, so it's always
            // safe to call getAvailableSlots directly here -- no draft-creation step needed.
            List<AgentSlot> slots = FieldServiceSchedulerFactory.getInstance().getAvailableSlots(
                sa.Id, AgentConfig.getSchedulingPolicyId()
            );
            List<Map<String, Object>> slotList = new List<Map<String, Object>>();
            for (AgentSlot s : slots) {
                slotList.add(new Map<String, Object>{
                    'start' => AgentDateUtil.toPacificHuman(s.startTime),
                    'end' => AgentDateUtil.toPacificHuman(s.finishTime),
                    'startIso' => AgentDateUtil.toIso(s.startTime),
                    'endIso' => AgentDateUtil.toIso(s.finishTime)
                });
            }
            Map<String, Object> result = new Map<String, Object>{
                'status' => 'ready',
                'confirmationNumber' => confirmationNumber,
                'slots' => slotList
            };
            if (slotList.isEmpty()) {
                result.put('message', 'No available appointment times in the next two weeks. This may need a human follow-up.');
            }
            return result;
        }

        // Commit mode: move to the newly chosen slot.
        Datetime windowStart = AgentDateUtil.parseIso(slotStartIso);
        Datetime windowEnd = AgentDateUtil.parseIso(slotEndIso);
        FSLScheduleOutcome outcome = FieldServiceSchedulerFactory.getInstance().scheduleAppointment(
            sa.Id, AgentConfig.getSchedulingPolicyId(), windowStart, windowEnd
        );
        if (!outcome.success) {
            throw new AgentApiException(outcome.errorMessage);
        }
        return new Map<String, Object>{
            'confirmationNumber' => confirmationNumber,
            'technician' => outcome.resourceName,
            'start' => AgentDateUtil.toPacificHuman(outcome.schedStart),
            'end' => AgentDateUtil.toPacificHuman(outcome.schedEnd)
        };
    }

    public static Map<String, Object> cancelAppointment(String confirmationNumber) {
        ServiceAppointment sa = findByConfirmationNumber(confirmationNumber);

        sa.Status = 'Canceled';
        Database.update(sa, AccessLevel.SYSTEM_MODE);

        if (sa.ParentRecordId != null) {
            Database.update(new WorkOrder(Id = sa.ParentRecordId, Status = 'Canceled'), AccessLevel.SYSTEM_MODE);
        }

        return new Map<String, Object>{
            'confirmationNumber' => confirmationNumber,
            'status' => 'Canceled'
        };
    }

    private static ServiceAppointment findByConfirmationNumber(String confirmationNumber) {
        if (String.isBlank(confirmationNumber)) {
            throw new AgentApiException('confirmationNumber is required.');
        }
        List<ServiceAppointment> matches = [
            SELECT Id, Status, ParentRecordId
            FROM ServiceAppointment
            WHERE AppointmentNumber = :confirmationNumber
            LIMIT 1
        ];
        if (matches.isEmpty()) {
            throw new AgentApiException('No appointment found with confirmation number "' + confirmationNumber + '".');
        }
        ServiceAppointment sa = matches[0];
        if (sa.Status == 'Canceled') {
            throw new AgentApiException('Appointment ' + confirmationNumber + ' is already canceled.');
        }
        if (sa.Status == 'Completed') {
            throw new AgentApiException('Appointment ' + confirmationNumber + ' has already been completed and can\'t be changed.');
        }
        return sa;
    }
}
