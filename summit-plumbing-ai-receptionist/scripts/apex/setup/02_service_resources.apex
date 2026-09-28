// Phase 2 setup: 4 Service Resources (technicians) with Metro Vancouver territory membership.
// Each technician needs a User record (Salesforce Platform license, Standard Platform User profile)
// since ServiceResource.RelatedRecordId must reference a User. These users never log in;
// they exist only so the FSL scheduling engine has resources to assign work to.
// Idempotent: safe to rerun.

String territoryName = 'Metro Vancouver';
Id orgSuffix = UserInfo.getOrganizationId();
String domain = String.valueOf(orgSuffix).toLowerCase().substring(0, 15) + '.demo';

ServiceTerritory st = [SELECT Id, OperatingHoursId FROM ServiceTerritory WHERE Name = :territoryName LIMIT 1];
Id platformProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard Platform User' LIMIT 1].Id;

// Home base per technician, spread across Metro Vancouver. Coordinates are
// approximate city-center values (not survey-precision) -- enough for FSL's
// travel-time work rules/objectives to compute, which need non-null geolocation.
// 'optimize' = 'true' for technicians the FSL scheduling engine can actually assign work
// to. This requires the technician's User to hold the "Field Service Scheduling" permission
// set license -- and this Developer Edition trial org only has 2 of those seats. So only
// Dave Chen and Maria Santos are schedulable; Kevin O'Brien and Priya Patel exist as data
// (for seed-data variety / a realistic-looking roster) but the FSL engine will never assign
// them a job. This is a real trial-org license cap, not a bug -- see README.
List<Map<String, String>> techs = new List<Map<String, String>>();
techs.add(new Map<String, String>{ 'first' => 'Dave', 'last' => 'Chen', 'alias' => 'dchen', 'city' => 'Burnaby', 'lat' => '49.2488', 'lng' => '-122.9805', 'optimize' => 'true' });
techs.add(new Map<String, String>{ 'first' => 'Maria', 'last' => 'Santos', 'alias' => 'msantos', 'city' => 'Richmond', 'lat' => '49.1666', 'lng' => '-123.1336', 'optimize' => 'true' });
techs.add(new Map<String, String>{ 'first' => 'Kevin', 'last' => 'O\'Brien', 'alias' => 'kobrien', 'city' => 'North Vancouver', 'lat' => '49.3200', 'lng' => '-123.0731', 'optimize' => 'false' });
techs.add(new Map<String, String>{ 'first' => 'Priya', 'last' => 'Patel', 'alias' => 'ppatel', 'city' => 'Surrey', 'lat' => '49.1913', 'lng' => '-122.8490', 'optimize' => 'false' });

Map<String, Id> permSetIdsByName = new Map<String, Id>();
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN ('FSL_Resource_Permissions', 'FSL_Resource_License')]) {
    permSetIdsByName.put(ps.Name, ps.Id);
}

for (Map<String, String> tech : techs) {
    String fullName = tech.get('first') + ' ' + tech.get('last');
    String username = tech.get('alias') + '.tech@' + domain;

    List<User> existingUsers = [SELECT Id FROM User WHERE Username = :username LIMIT 1];
    User u;
    if (existingUsers.isEmpty()) {
        u = new User(
            FirstName = tech.get('first'),
            LastName = tech.get('last'),
            Username = username,
            Email = username,
            Alias = tech.get('alias'),
            ProfileId = platformProfileId,
            TimeZoneSidKey = 'America/Vancouver',
            LocaleSidKey = 'en_CA',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            UserPermissionsSFContentUser = false
        );
        insert u;
        System.debug('Created User: ' + fullName + ' -> ' + u.Id);
    } else {
        u = existingUsers[0];
        System.debug('User already exists: ' + fullName + ' -> ' + u.Id);
    }

    Boolean shouldOptimize = tech.get('optimize') == 'true';

    if (shouldOptimize) {
        for (String psName : new List<String>{ 'FSL_Resource_License', 'FSL_Resource_Permissions' }) {
            Id psId = permSetIdsByName.get(psName);
            if (psId == null) continue;
            List<PermissionSetAssignment> existingPsa = [
                SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :u.Id AND PermissionSetId = :psId LIMIT 1
            ];
            if (existingPsa.isEmpty()) {
                try {
                    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
                    System.debug('Assigned ' + psName + ' to ' + fullName);
                } catch (Exception e) {
                    System.debug('Could NOT assign ' + psName + ' to ' + fullName + ': ' + e.getMessage());
                }
            }
        }
    }

    List<ServiceResource> existingSr = [SELECT Id, IsOptimizationCapable FROM ServiceResource WHERE RelatedRecordId = :u.Id LIMIT 1];
    ServiceResource sr;
    if (existingSr.isEmpty()) {
        sr = new ServiceResource(
            Name = fullName,
            RelatedRecordId = u.Id,
            ResourceType = 'T',
            IsActive = true,
            IsOptimizationCapable = shouldOptimize
        );
        try {
            insert sr;
            System.debug('Created ServiceResource: ' + fullName + ' -> ' + sr.Id);
        } catch (Exception e) {
            System.debug('Created ServiceResource without optimization flag (permset likely missing): ' + fullName + ' - ' + e.getMessage());
            sr.IsOptimizationCapable = false;
            insert sr;
        }
    } else {
        sr = existingSr[0];
        System.debug('ServiceResource already exists: ' + fullName + ' -> ' + sr.Id);
        if (sr.IsOptimizationCapable != shouldOptimize) {
            try {
                sr.IsOptimizationCapable = shouldOptimize;
                update sr;
                System.debug('Updated IsOptimizationCapable=' + shouldOptimize + ' for ' + fullName);
            } catch (Exception e) {
                System.debug('Could NOT update IsOptimizationCapable for ' + fullName + ': ' + e.getMessage());
            }
        }
    }

    Decimal techLat = Decimal.valueOf(tech.get('lat'));
    Decimal techLng = Decimal.valueOf(tech.get('lng'));

    List<ServiceTerritoryMember> existingStm = [
        SELECT Id, Latitude, Longitude FROM ServiceTerritoryMember
        WHERE ServiceResourceId = :sr.Id AND ServiceTerritoryId = :st.Id
        LIMIT 1
    ];
    if (existingStm.isEmpty()) {
        ServiceTerritoryMember stm = new ServiceTerritoryMember(
            ServiceResourceId = sr.Id,
            ServiceTerritoryId = st.Id,
            TerritoryType = 'P',
            OperatingHoursId = st.OperatingHoursId,
            EffectiveStartDate = Date.today(),
            City = tech.get('city'),
            State = 'British Columbia',
            Country = 'Canada',
            Latitude = techLat,
            Longitude = techLng
        );
        insert stm;
        System.debug('Created ServiceTerritoryMember for ' + fullName);
    } else {
        ServiceTerritoryMember stm = existingStm[0];
        if (stm.Latitude == null || stm.Longitude == null) {
            stm.Latitude = techLat;
            stm.Longitude = techLng;
            stm.City = tech.get('city');
            stm.State = 'British Columbia';
            stm.Country = 'Canada';
            update stm;
            System.debug('Backfilled geolocation on ServiceTerritoryMember for ' + fullName);
        } else {
            System.debug('ServiceTerritoryMember already exists for ' + fullName);
        }
    }
}

System.debug('=== DONE seeding 4 technicians ===');
