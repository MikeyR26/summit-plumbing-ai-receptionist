public class AgentDateUtil {
    public static Datetime parseIso(String iso) {
        if (String.isBlank(iso)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
        } catch (Exception e) {
            throw new AgentApiException('Could not parse date/time "' + iso + '". Expected ISO 8601 format, e.g. 2026-09-28T16:00:00Z.');
        }
    }

    public static String toIso(Datetime dt) {
        if (dt == null) {
            return null;
        }
        return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    public static String toPacificHuman(Datetime dt) {
        if (dt == null) {
            return null;
        }
        return dt.format('EEE, MMM d, h:mm a', AgentConfig.TIMEZONE);
    }
}
