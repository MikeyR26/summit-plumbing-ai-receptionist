// Seam around the FSL managed package's scheduling engine. FSL.AppointmentBookingService
// and FSL.ScheduleService can't be exercised in Apex tests (they need real territory/resource/
// operating-hours/policy config and perform real callouts), so all production code talks to
// this interface instead, and tests inject a mock implementation.
public interface IFieldServiceScheduler {
    List<AgentSlot> getAvailableSlots(Id serviceAppointmentId, Id schedulingPolicyId);
    FSLScheduleOutcome scheduleAppointment(Id serviceAppointmentId, Id schedulingPolicyId, Datetime windowStart, Datetime windowEnd);
}
