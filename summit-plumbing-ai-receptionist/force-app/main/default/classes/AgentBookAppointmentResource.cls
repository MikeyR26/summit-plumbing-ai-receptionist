@RestResource(urlMapping='/agent/v1/bookAppointment')
global with sharing class AgentBookAppointmentResource {
    @HttpPost
    global static void bookAppointment() {
        RestResponse res = RestContext.response;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());
            Id serviceAppointmentId = body.get('serviceAppointmentId') != null ? (Id) String.valueOf(body.get('serviceAppointmentId')) : null;
            String slotStartIso = (String) body.get('slotStartIso');
            String slotEndIso = (String) body.get('slotEndIso');

            Map<String, Object> data = AgentSchedulingService.bookAppointment(serviceAppointmentId, slotStartIso, slotEndIso);
            AgentApiResponse.writeSuccess(res, data);
        } catch (AgentApiException e) {
            AgentApiResponse.writeError(res, 400, e.getMessage(), 'BAD_REQUEST');
        } catch (Exception e) {
            AgentApiResponse.writeError(res, 500, 'Unexpected error: ' + e.getMessage(), 'INTERNAL_ERROR');
        }
    }
}
