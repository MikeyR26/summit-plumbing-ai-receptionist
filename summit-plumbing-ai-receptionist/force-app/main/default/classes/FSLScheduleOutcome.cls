public class FSLScheduleOutcome {
    public Boolean success;
    public String resourceName;
    public Datetime schedStart;
    public Datetime schedEnd;
    public String errorMessage;

    public FSLScheduleOutcome(Boolean success, String resourceName, Datetime schedStart, Datetime schedEnd, String errorMessage) {
        this.success = success;
        this.resourceName = resourceName;
        this.schedStart = schedStart;
        this.schedEnd = schedEnd;
        this.errorMessage = errorMessage;
    }
}
