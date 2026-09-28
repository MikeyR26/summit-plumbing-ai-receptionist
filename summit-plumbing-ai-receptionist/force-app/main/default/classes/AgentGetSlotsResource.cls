@RestResource(urlMapping='/agent/v1/getSlots')
global with sharing class AgentGetSlotsResource {
    @HttpPost
    global static void getSlots() {
        RestResponse res = RestContext.response;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());
            Id customerId = body.get('customerId') != null ? (Id) String.valueOf(body.get('customerId')) : null;
            String jobType = (String) body.get('jobType');
            Id serviceAppointmentId = body.get('serviceAppointmentId') != null ? (Id) String.valueOf(body.get('serviceAppointmentId')) : null;

            Map<String, Object> data = AgentSchedulingService.getSlots(customerId, jobType, serviceAppointmentId);
            AgentApiResponse.writeSuccess(res, data);
        } catch (AgentOutsideTerritoryException e) {
            AgentApiResponse.writeError(res, 422, e.getMessage(), 'OUTSIDE_TERRITORY');
        } catch (AgentApiException e) {
            AgentApiResponse.writeError(res, 400, e.getMessage(), 'BAD_REQUEST');
        } catch (Exception e) {
            AgentApiResponse.writeError(res, 500, 'Unexpected error: ' + e.getMessage(), 'INTERNAL_ERROR');
        }
    }
}
