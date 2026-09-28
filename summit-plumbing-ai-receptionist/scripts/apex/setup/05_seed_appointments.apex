// Phase 2 setup: seed a week of existing appointments (WorkOrder + ServiceAppointment),
// spread across the 4 technicians and 4 work types, so the calendar isn't empty for the demo.
//
// NOTE: this seed script writes SchedStartTime/SchedEndTime directly, which is fine for
// historical/pre-existing demo data. The Phase 3 Apex REST API (the agent's booking path)
// must NOT do this -- it has to go through FSL.ScheduleService / FSL.AppointmentBookingService.
//
// Idempotent: skips any (technician, start time) pair that already has an appointment.
// Times are computed as fixed Pacific-time wall-clock hours converted to UTC assuming PDT
// (UTC-7), which holds for the demo's seeding window (Sep-Oct).

Integer pacificOffsetHours = 7; // PDT (UTC-7). Would need to be 8 for PST (Nov-Mar).

// Approximate city-center coordinates (not survey-precision) -- enough for
// FSL's travel-time work rules/objectives to compute, which need non-null geolocation.
Map<String, List<Decimal>> cityCoords = new Map<String, List<Decimal>>{
    'Vancouver' => new List<Decimal>{ 49.2827, -123.1207 },
    'Richmond' => new List<Decimal>{ 49.1666, -123.1336 },
    'Burnaby' => new List<Decimal>{ 49.2488, -122.9805 },
    'Coquitlam' => new List<Decimal>{ 49.2838, -122.7932 },
    'New Westminster' => new List<Decimal>{ 49.2057, -122.9110 },
    'North Vancouver' => new List<Decimal>{ 49.3200, -123.0731 },
    'West Vancouver' => new List<Decimal>{ 49.3283, -123.1594 },
    'Surrey' => new List<Decimal>{ 49.1913, -122.8490 },
    'Delta' => new List<Decimal>{ 49.0847, -123.0586 },
    'Langley' => new List<Decimal>{ 49.1044, -122.6603 }
};

ServiceTerritory territory = [SELECT Id FROM ServiceTerritory WHERE Name = 'Metro Vancouver' LIMIT 1];

// Backfill geolocation on any previously-seeded appointments that predate this update.
List<ServiceAppointment> saToBackfill = [
    SELECT Id, City FROM ServiceAppointment
    WHERE ServiceTerritoryId = :territory.Id AND Latitude = null AND City != null
];
if (!saToBackfill.isEmpty()) {
    for (ServiceAppointment sa : saToBackfill) {
        if (cityCoords.containsKey(sa.City)) {
            sa.Latitude = cityCoords.get(sa.City)[0];
            sa.Longitude = cityCoords.get(sa.City)[1];
        }
    }
    update saToBackfill;
    System.debug('Backfilled geolocation on ' + saToBackfill.size() + ' existing ServiceAppointments');
}
List<WorkOrder> woToBackfill = [
    SELECT Id, City FROM WorkOrder
    WHERE ServiceTerritoryId = :territory.Id AND Latitude = null AND City != null
];
if (!woToBackfill.isEmpty()) {
    for (WorkOrder wo : woToBackfill) {
        if (cityCoords.containsKey(wo.City)) {
            wo.Latitude = cityCoords.get(wo.City)[0];
            wo.Longitude = cityCoords.get(wo.City)[1];
        }
    }
    update woToBackfill;
    System.debug('Backfilled geolocation on ' + woToBackfill.size() + ' existing WorkOrders');
}

Map<String, Id> workTypeIds = new Map<String, Id>();
for (WorkType wt : [SELECT Id, Name FROM WorkType WHERE Name IN ('Drain Cleaning', 'Water Heater Install', 'Leak Repair', 'Emergency Call-out')]) {
    workTypeIds.put(wt.Name, wt.Id);
}
List<String> workTypeOrder = new List<String>{ 'Drain Cleaning', 'Water Heater Install', 'Leak Repair', 'Emergency Call-out' };
Map<String, Decimal> durationHours = new Map<String, Decimal>{
    'Drain Cleaning' => 1.0, 'Water Heater Install' => 3.0, 'Leak Repair' => 2.0, 'Emergency Call-out' => 1.5
};
List<String> saturdayEligibleWorkTypes = new List<String>{ 'Drain Cleaning', 'Leak Repair', 'Emergency Call-out' }; // skip 3h install, doesn't fit 9-1 window

List<ServiceResource> resources = [SELECT Id, Name FROM ServiceResource WHERE IsActive = true ORDER BY Name];

List<Contact> customers = [
    SELECT Id, AccountId, FirstName, LastName, Account.BillingStreet, Account.BillingCity,
           Account.BillingState, Account.BillingPostalCode, Account.BillingCountry
    FROM Contact
    WHERE Account.BillingCity IN ('Vancouver', 'Richmond', 'Burnaby', 'Coquitlam', 'New Westminster', 'North Vancouver', 'West Vancouver', 'Surrey', 'Delta', 'Langley')
    ORDER BY Account.Name
    LIMIT 30
];

if (resources.size() != 4 || customers.size() < 20) {
    System.debug('=== ABORT: expected 4 service resources and >=20 seeded customers. Found ' + resources.size() + ' resources, ' + customers.size() + ' customers. Run scripts 02 and 04 first. ===');
} else {
    Integer customerCursor = 0;
    Integer created = 0;
    Integer skipped = 0;
    List<WorkOrder> workOrdersToInsert = new List<WorkOrder>();
    List<Map<String, Object>> plannedAppointments = new List<Map<String, Object>>();

    for (Integer dayOffset = 1; dayOffset <= 7; dayOffset++) {
        Date d = Date.today().addDays(dayOffset);
        Datetime dRef = Datetime.newInstanceGmt(d, Time.newInstance(0, 0, 0, 0));
        String dayName = dRef.formatGmt('EEEE');

        if (dayName == 'Sunday') {
            continue; // closed
        }

        List<Integer> slotHours = (dayName == 'Saturday') ? new List<Integer>{ 9, 11 } : new List<Integer>{ 9, 11, 14 };
        List<String> eligibleTypes = (dayName == 'Saturday') ? saturdayEligibleWorkTypes : workTypeOrder;

        for (Integer i = 0; i < slotHours.size(); i++) {
            Integer techIdx = Math.mod(dayOffset + i, resources.size());
            String wtName = eligibleTypes[Math.mod(dayOffset + i, eligibleTypes.size())];
            ServiceResource resource = resources[techIdx];
            Contact customer = customers[Math.mod(customerCursor, customers.size())];
            customerCursor++;

            Integer startHourPacific = slotHours[i];
            Decimal durHours = durationHours.get(wtName);
            Integer durMinutes = (durHours * 60).intValue();
            List<Decimal> coords = cityCoords.get(customer.Account.BillingCity);
            Decimal custLat = coords != null ? coords[0] : null;
            Decimal custLng = coords != null ? coords[1] : null;

            Time startTimeGmt = Time.newInstance(startHourPacific + pacificOffsetHours, 0, 0, 0);
            Datetime schedStart = Datetime.newInstanceGmt(d, startTimeGmt);
            Datetime schedEnd = schedStart.addMinutes(durMinutes);

            List<ServiceAppointment> existing = [
                SELECT Id FROM ServiceAppointment
                WHERE SchedStartTime = :schedStart
                AND Id IN (SELECT ServiceAppointmentId FROM AssignedResource WHERE ServiceResourceId = :resource.Id)
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                skipped++;
                continue;
            }

            WorkOrder wo = new WorkOrder(
                Subject = wtName + ' - ' + customer.FirstName + ' ' + customer.LastName,
                AccountId = customer.AccountId,
                ContactId = customer.Id,
                WorkTypeId = workTypeIds.get(wtName),
                ServiceTerritoryId = territory.Id,
                Status = 'New',
                StartDate = schedStart,
                Street = customer.Account.BillingStreet,
                City = customer.Account.BillingCity,
                State = customer.Account.BillingState,
                PostalCode = customer.Account.BillingPostalCode,
                Country = customer.Account.BillingCountry,
                Latitude = custLat,
                Longitude = custLng
            );
            workOrdersToInsert.add(wo);
            plannedAppointments.add(new Map<String, Object>{
                'workOrder' => wo,
                'resourceId' => resource.Id,
                'workTypeId' => workTypeIds.get(wtName),
                'schedStart' => schedStart,
                'schedEnd' => schedEnd,
                'durMinutes' => durMinutes,
                'street' => customer.Account.BillingStreet,
                'city' => customer.Account.BillingCity,
                'state' => customer.Account.BillingState,
                'postalCode' => customer.Account.BillingPostalCode,
                'country' => customer.Account.BillingCountry,
                'lat' => custLat,
                'lng' => custLng
            });
        }
    }

    if (!workOrdersToInsert.isEmpty()) {
        insert workOrdersToInsert;

        List<ServiceAppointment> appointmentsToInsert = new List<ServiceAppointment>();
        for (Map<String, Object> plan : plannedAppointments) {
            WorkOrder wo = (WorkOrder) plan.get('workOrder');
            appointmentsToInsert.add(new ServiceAppointment(
                ParentRecordId = wo.Id,
                WorkTypeId = (Id) plan.get('workTypeId'),
                ServiceTerritoryId = territory.Id,
                Status = 'None',
                SchedStartTime = (Datetime) plan.get('schedStart'),
                SchedEndTime = (Datetime) plan.get('schedEnd'),
                ArrivalWindowStartTime = (Datetime) plan.get('schedStart'),
                ArrivalWindowEndTime = (Datetime) plan.get('schedEnd'),
                Street = (String) plan.get('street'),
                City = (String) plan.get('city'),
                State = (String) plan.get('state'),
                PostalCode = (String) plan.get('postalCode'),
                Country = (String) plan.get('country'),
                Latitude = (Decimal) plan.get('lat'),
                Longitude = (Decimal) plan.get('lng')
            ));
        }
        insert appointmentsToInsert;

        for (ServiceAppointment sa : appointmentsToInsert) {
            sa.Status = 'Scheduled';
        }
        update appointmentsToInsert;

        List<AssignedResource> assignments = new List<AssignedResource>();
        for (Integer i = 0; i < appointmentsToInsert.size(); i++) {
            assignments.add(new AssignedResource(
                ServiceAppointmentId = appointmentsToInsert[i].Id,
                ServiceResourceId = (Id) plannedAppointments[i].get('resourceId')
            ));
        }
        insert assignments;

        created = appointmentsToInsert.size();
    }

    System.debug('=== DONE seeding appointments: created=' + created + ' skipped=' + skipped + ' ===');
}
