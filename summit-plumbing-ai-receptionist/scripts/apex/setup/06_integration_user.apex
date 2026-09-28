// Phase 4 setup: dedicated integration User for the AI agent's OAuth client-credentials
// connection. Two profiles failed before this one:
//   - "Minimum Access - API Only Integrations" (Salesforce Integration license): insert threw
//     "The user license doesn't allow Visualforce Page Access" -- a default-landing-page quirk.
//   - "Standard Platform User" (Salesforce Platform license, same profile the 4 technician
//     users successfully use): insert threw "The user license doesn't allow the permission:
//     Read Entitlement". Platform licenses don't support Entitlement Management, and
//     something in this org (likely Field Service enablement, which touches Service Cloud
//     features) now defaults new users toward an entitlement-related permission that
//     Platform can't hold -- this didn't happen when the technicians were created earlier
//     in the session, so it's an org-state change, not a one-off fluke.
// "Standard User" (full Salesforce license, which does support entitlements) works. Our Apex
// service layer runs in system mode for CRUD, so this user only needs: Apex class access to
// the 6 REST resource classes (via the Agent_Integration_User permission set) and the FSL
// "Call Center Rep" permission set (FSL.ScheduleService/AppointmentBookingService enforce
// their own permission checks regardless of Apex system mode -- see Phase 1/3 findings).
// Idempotent: safe to rerun.

String username = 'agent.integration@00dg800000knzcr.demo';

List<User> existingUsers = [SELECT Id FROM User WHERE Username = :username LIMIT 1];
User u;
if (existingUsers.isEmpty()) {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
    u = new User(
        FirstName = 'Agent',
        LastName = 'Integration',
        Username = username,
        Email = username,
        Alias = 'agentint',
        ProfileId = profileId,
        TimeZoneSidKey = 'America/Vancouver',
        LocaleSidKey = 'en_CA',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        UserPermissionsSFContentUser = false
    );
    insert u;
    System.debug('Created integration User: ' + u.Id);
} else {
    u = existingUsers[0];
    System.debug('Integration User already exists: ' + u.Id);
}

Map<String, Id> permSetIdsByName = new Map<String, Id>();
for (PermissionSet ps : [
    SELECT Id, Name FROM PermissionSet
    WHERE Name IN ('Agent_Integration_User', 'FSL_Agent_Permissions', 'FSL_Agent_License')
]) {
    permSetIdsByName.put(ps.Name, ps.Id);
}

for (String psName : new List<String>{ 'Agent_Integration_User', 'FSL_Agent_License', 'FSL_Agent_Permissions' }) {
    Id psId = permSetIdsByName.get(psName);
    if (psId == null) {
        System.debug('Permission set not found (skipping): ' + psName);
        continue;
    }
    List<PermissionSetAssignment> existingPsa = [
        SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :u.Id AND PermissionSetId = :psId LIMIT 1
    ];
    if (existingPsa.isEmpty()) {
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
        System.debug('Assigned ' + psName);
    } else {
        System.debug('Already assigned: ' + psName);
    }
}

System.debug('=== DONE: integration user ' + u.Id + ' ===');
