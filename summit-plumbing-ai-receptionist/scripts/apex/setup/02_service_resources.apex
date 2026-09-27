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

List<Map<String, String>> techs = new List<Map<String, String>>();
techs.add(new Map<String, String>{ 'first' => 'Dave', 'last' => 'Chen', 'alias' => 'dchen' });
techs.add(new Map<String, String>{ 'first' => 'Maria', 'last' => 'Santos', 'alias' => 'msantos' });
techs.add(new Map<String, String>{ 'first' => 'Kevin', 'last' => 'O\'Brien', 'alias' => 'kobrien' });
techs.add(new Map<String, String>{ 'first' => 'Priya', 'last' => 'Patel', 'alias' => 'ppatel' });

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

    List<ServiceResource> existingSr = [SELECT Id FROM ServiceResource WHERE RelatedRecordId = :u.Id LIMIT 1];
    ServiceResource sr;
    if (existingSr.isEmpty()) {
        sr = new ServiceResource(
            Name = fullName,
            RelatedRecordId = u.Id,
            ResourceType = 'T',
            IsActive = true
        );
        insert sr;
        System.debug('Created ServiceResource: ' + fullName + ' -> ' + sr.Id);
    } else {
        sr = existingSr[0];
        System.debug('ServiceResource already exists: ' + fullName + ' -> ' + sr.Id);
    }

    List<ServiceTerritoryMember> existingStm = [
        SELECT Id FROM ServiceTerritoryMember
        WHERE ServiceResourceId = :sr.Id AND ServiceTerritoryId = :st.Id
        LIMIT 1
    ];
    if (existingStm.isEmpty()) {
        ServiceTerritoryMember stm = new ServiceTerritoryMember(
            ServiceResourceId = sr.Id,
            ServiceTerritoryId = st.Id,
            TerritoryType = 'P',
            OperatingHoursId = st.OperatingHoursId,
            EffectiveStartDate = Date.today()
        );
        insert stm;
        System.debug('Created ServiceTerritoryMember for ' + fullName);
    } else {
        System.debug('ServiceTerritoryMember already exists for ' + fullName);
    }
}

System.debug('=== DONE seeding 4 technicians ===');
