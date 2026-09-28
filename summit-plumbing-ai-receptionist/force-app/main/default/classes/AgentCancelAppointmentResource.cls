@RestResource(urlMapping='/agent/v1/cancelAppointment')
global with sharing class AgentCancelAppointmentResource {
    @HttpPost
    global static void cancelAppointment() {
        RestResponse res = RestContext.response;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());
            String confirmationNumber = (String) body.get('confirmationNumber');

            Map<String, Object> data = AgentSchedulingService.cancelAppointment(confirmationNumber);
            AgentApiResponse.writeSuccess(res, data);
        } catch (AgentApiException e) {
            AgentApiResponse.writeError(res, 400, e.getMessage(), 'BAD_REQUEST');
        } catch (Exception e) {
            AgentApiResponse.writeError(res, 500, 'Unexpected error: ' + e.getMessage(), 'INTERNAL_ERROR');
        }
    }
}
