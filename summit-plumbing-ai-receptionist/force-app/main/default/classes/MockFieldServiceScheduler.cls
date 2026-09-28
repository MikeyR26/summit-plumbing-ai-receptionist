// Test double for IFieldServiceScheduler. FSL.AppointmentBookingService/ScheduleService can't
// be exercised in Apex tests (real callouts, real territory/policy config needed), so tests
// inject this instead via FieldServiceSchedulerFactory.setTestInstance().
@isTest
public class MockFieldServiceScheduler implements IFieldServiceScheduler {
    public List<AgentSlot> slotsToReturn = new List<AgentSlot>();
    public FSLScheduleOutcome outcomeToReturn;

    public List<AgentSlot> getAvailableSlots(Id serviceAppointmentId, Id schedulingPolicyId) {
        return slotsToReturn;
    }

    public FSLScheduleOutcome scheduleAppointment(Id serviceAppointmentId, Id schedulingPolicyId, Datetime windowStart, Datetime windowEnd) {
        return outcomeToReturn;
    }
}
