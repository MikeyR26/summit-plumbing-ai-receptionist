@RestResource(urlMapping='/agent/v1/rescheduleAppointment')
global with sharing class AgentRescheduleAppointmentResource {
    @HttpPost
    global static void rescheduleAppointment() {
        RestResponse res = RestContext.response;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());
            String confirmationNumber = (String) body.get('confirmationNumber');
            String slotStartIso = (String) body.get('slotStartIso');
            String slotEndIso = (String) body.get('slotEndIso');

            Map<String, Object> data = AgentSchedulingService.rescheduleAppointment(confirmationNumber, slotStartIso, slotEndIso);
            AgentApiResponse.writeSuccess(res, data);
        } catch (AgentApiException e) {
            AgentApiResponse.writeError(res, 400, e.getMessage(), 'BAD_REQUEST');
        } catch (Exception e) {
            AgentApiResponse.writeError(res, 500, 'Unexpected error: ' + e.getMessage(), 'INTERNAL_ERROR');
        }
    }
}
