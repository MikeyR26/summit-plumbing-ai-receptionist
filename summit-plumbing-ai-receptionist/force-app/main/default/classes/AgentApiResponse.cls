public class AgentApiResponse {
    public static void writeSuccess(RestResponse res, Map<String, Object> data) {
        write(res, 200, new Map<String, Object>{ 'ok' => true, 'data' => data });
    }

    public static void writeError(RestResponse res, Integer statusCode, String message, String code) {
        write(res, statusCode, new Map<String, Object>{ 'ok' => false, 'error' => message, 'code' => code });
    }

    private static void write(RestResponse res, Integer statusCode, Map<String, Object> body) {
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
