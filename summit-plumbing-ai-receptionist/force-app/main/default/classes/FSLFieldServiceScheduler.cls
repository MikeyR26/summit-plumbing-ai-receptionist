// Real implementation backed by the FSL managed package's scheduling engine.
//
// getAvailableSlots() performs an external callout (travel-time grading) once real candidate
// resources exist. The ServiceAppointment it's called against MUST already be committed in a
// prior transaction -- calling this in the same transaction as the DML that created that
// ServiceAppointment throws "You have uncommitted work pending" (verified by hand before
// writing this class). Callers must split appointment creation and slot lookup across two
// separate Apex REST invocations.
// without sharing: same reasoning as AgentSchedulingService -- backend integration API.
public without sharing class FSLFieldServiceScheduler implements IFieldServiceScheduler {

    public List<AgentSlot> getAvailableSlots(Id serviceAppointmentId, Id schedulingPolicyId) {
        ServiceAppointment sa = [
            SELECT Id, ServiceTerritory.OperatingHoursId
            FROM ServiceAppointment
            WHERE Id = :serviceAppointmentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        System.TimeZone tz = System.TimeZone.getTimeZone(AgentConfig.TIMEZONE);
        List<FSL.AppointmentBookingSlot> raw = FSL.AppointmentBookingService.getSlots(
            serviceAppointmentId,
            schedulingPolicyId,
            sa.ServiceTerritory.OperatingHoursId,
            tz,
            false
        );

        List<AgentSlot> results = new List<AgentSlot>();
        if (raw != null) {
            for (FSL.AppointmentBookingSlot slot : raw) {
                // FSL returns interval.Start/Finish as wall-clock values in `tz` but stored
                // in the Datetime's UTC fields uncorrected (e.g. Pacific "8:00 AM" comes back
                // internally as UTC 08:00, not the true UTC instant 15:00). This offset
                // correction is documented in Salesforce's own conversion examples for this
                // API and was confirmed necessary by hand (uncorrected values displayed 7
                // hours early). Must correct before using these as real UTC Datetimes.
                Datetime correctedStart = slot.interval.Start.addSeconds(tz.getOffset(slot.interval.Start) / -1000);
                Datetime correctedFinish = slot.interval.Finish.addSeconds(tz.getOffset(slot.interval.Finish) / -1000);
                results.add(new AgentSlot(correctedStart, correctedFinish, slot.grade));
            }
        }
        return results;
    }

    public FSLScheduleOutcome scheduleAppointment(Id serviceAppointmentId, Id schedulingPolicyId, Datetime windowStart, Datetime windowEnd) {
        ServiceAppointment sa = new ServiceAppointment(
            Id = serviceAppointmentId,
            Status = 'None',
            ArrivalWindowStartTime = windowStart,
            ArrivalWindowEndTime = windowEnd
        );
        Database.update(sa, AccessLevel.SYSTEM_MODE);

        FSL.ScheduleResult result = FSL.ScheduleService.schedule(schedulingPolicyId, serviceAppointmentId);

        if (result == null) {
            // FSL.ScheduleService.schedule() returns null on failure with no error detail --
            // this is documented FSL behavior, not a bug in this wrapper.
            return new FSLScheduleOutcome(false, null, null, null, 'That time could not be booked -- it may have just been taken.');
        }

        return new FSLScheduleOutcome(
            true,
            result.Resource != null ? result.Resource.Name : null,
            result.Service != null ? result.Service.SchedStartTime : null,
            result.Service != null ? result.Service.SchedEndTime : null,
            null
        );
    }
}
