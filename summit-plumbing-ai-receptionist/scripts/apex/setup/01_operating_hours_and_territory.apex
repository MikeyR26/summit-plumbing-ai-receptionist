// Phase 2 setup: Operating Hours (Mon-Fri 8-5, Sat 9-1, Pacific time) + Service Territory (Metro Vancouver).
// Idempotent: safe to rerun.

String territoryName = 'Metro Vancouver';
String hoursName = 'Metro Vancouver Business Hours';

OperatingHours oh;
List<OperatingHours> existingOh = [SELECT Id FROM OperatingHours WHERE Name = :hoursName LIMIT 1];
if (existingOh.isEmpty()) {
    oh = new OperatingHours(Name = hoursName, TimeZone = 'America/Vancouver');
    insert oh;
    System.debug('Created OperatingHours: ' + oh.Id);
} else {
    oh = existingOh[0];
    System.debug('OperatingHours already exists: ' + oh.Id);
}

List<TimeSlot> existingSlots = [SELECT Id FROM TimeSlot WHERE OperatingHoursId = :oh.Id];
if (existingSlots.isEmpty()) {
    List<TimeSlot> slots = new List<TimeSlot>();
    List<String> weekdays = new List<String>{'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'};
    for (String day : weekdays) {
        slots.add(new TimeSlot(
            OperatingHoursId = oh.Id,
            DayOfWeek = day,
            StartTime = Time.newInstance(8, 0, 0, 0),
            EndTime = Time.newInstance(17, 0, 0, 0)
        ));
    }
    slots.add(new TimeSlot(
        OperatingHoursId = oh.Id,
        DayOfWeek = 'Saturday',
        StartTime = Time.newInstance(9, 0, 0, 0),
        EndTime = Time.newInstance(13, 0, 0, 0)
    ));
    insert slots;
    System.debug('Created ' + slots.size() + ' time slots');
} else {
    System.debug('Time slots already exist (' + existingSlots.size() + ' found)');
}

// Approximate downtown Vancouver coordinates. Good enough for FSL travel-time
// objectives/work rules (e.g. "Maximum Travel From Home"), which need SOME
// geolocation to compute -- not survey-precision, just non-null.
Decimal territoryLat = 49.2827;
Decimal territoryLng = -123.1207;

ServiceTerritory st;
List<ServiceTerritory> existingSt = [SELECT Id, Latitude, Longitude FROM ServiceTerritory WHERE Name = :territoryName LIMIT 1];
if (existingSt.isEmpty()) {
    st = new ServiceTerritory(
        Name = territoryName,
        IsActive = true,
        OperatingHoursId = oh.Id,
        Street = '800 Robson St',
        City = 'Vancouver',
        State = 'British Columbia',
        PostalCode = 'V6Z 3B7',
        Country = 'Canada',
        Latitude = territoryLat,
        Longitude = territoryLng
    );
    insert st;
    System.debug('Created ServiceTerritory: ' + st.Id);
} else {
    st = existingSt[0];
    if (st.Latitude == null || st.Longitude == null) {
        st.Latitude = territoryLat;
        st.Longitude = territoryLng;
        update st;
        System.debug('Backfilled geolocation on ServiceTerritory: ' + st.Id);
    } else {
        System.debug('ServiceTerritory already exists: ' + st.Id);
    }
}

System.debug('=== DONE: OperatingHours=' + oh.Id + ' ServiceTerritory=' + st.Id + ' ===');
