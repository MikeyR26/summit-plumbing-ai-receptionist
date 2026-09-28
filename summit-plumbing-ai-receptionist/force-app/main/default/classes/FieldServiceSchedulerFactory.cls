public class FieldServiceSchedulerFactory {
    @TestVisible
    private static IFieldServiceScheduler testOverride;

    public static IFieldServiceScheduler getInstance() {
        if (testOverride != null) {
            return testOverride;
        }
        return new FSLFieldServiceScheduler();
    }

    @TestVisible
    private static void setTestInstance(IFieldServiceScheduler mock) {
        testOverride = mock;
    }
}
