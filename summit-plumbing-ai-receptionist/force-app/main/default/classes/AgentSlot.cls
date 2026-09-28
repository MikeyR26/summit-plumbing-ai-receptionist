public class AgentSlot {
    public Datetime startTime;
    public Datetime finishTime;
    public Decimal grade;

    public AgentSlot(Datetime startTime, Datetime finishTime, Decimal grade) {
        this.startTime = startTime;
        this.finishTime = finishTime;
        this.grade = grade;
    }
}
