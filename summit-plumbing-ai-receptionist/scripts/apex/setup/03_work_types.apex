// Phase 2 setup: Work Types (Drain Cleaning 1h, Water Heater Install 3h, Leak Repair 2h,
// Emergency Call-out 1.5h), linked to the Metro Vancouver territory.
// ShouldAutoCreateSvcAppt = false: our Apex REST API (Phase 3) creates WorkOrder +
// ServiceAppointment explicitly via the FSL scheduling engine, rather than relying on
// WorkOrder-insert automation.
// Idempotent: safe to rerun.

ServiceTerritory st = [SELECT Id FROM ServiceTerritory WHERE Name = 'Metro Vancouver' LIMIT 1];

List<Map<String, Object>> defs = new List<Map<String, Object>>();
defs.add(new Map<String, Object>{ 'name' => 'Drain Cleaning', 'duration' => 1.0 });
defs.add(new Map<String, Object>{ 'name' => 'Water Heater Install', 'duration' => 3.0 });
defs.add(new Map<String, Object>{ 'name' => 'Leak Repair', 'duration' => 2.0 });
defs.add(new Map<String, Object>{ 'name' => 'Emergency Call-out', 'duration' => 1.5 });

for (Map<String, Object> def : defs) {
    String wtName = (String) def.get('name');

    List<WorkType> existingWt = [SELECT Id FROM WorkType WHERE Name = :wtName LIMIT 1];
    WorkType wt;
    if (existingWt.isEmpty()) {
        wt = new WorkType(
            Name = wtName,
            EstimatedDuration = (Decimal) def.get('duration'),
            DurationType = 'Hours',
            ShouldAutoCreateSvcAppt = false
        );
        insert wt;
        System.debug('Created WorkType: ' + wtName + ' -> ' + wt.Id);
    } else {
        wt = existingWt[0];
        System.debug('WorkType already exists: ' + wtName + ' -> ' + wt.Id);
    }

    List<ServiceTerritoryWorkType> existingStwt = [
        SELECT Id FROM ServiceTerritoryWorkType
        WHERE WorkTypeId = :wt.Id AND ServiceTerritoryId = :st.Id
        LIMIT 1
    ];
    if (existingStwt.isEmpty()) {
        insert new ServiceTerritoryWorkType(WorkTypeId = wt.Id, ServiceTerritoryId = st.Id);
        System.debug('Linked WorkType to territory: ' + wtName);
    } else {
        System.debug('WorkType already linked to territory: ' + wtName);
    }
}

System.debug('=== DONE seeding 4 work types ===');
