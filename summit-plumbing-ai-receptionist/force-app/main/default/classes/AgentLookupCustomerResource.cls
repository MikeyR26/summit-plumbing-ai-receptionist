@RestResource(urlMapping='/agent/v1/lookupCustomer')
global with sharing class AgentLookupCustomerResource {
    @HttpPost
    global static void lookupCustomer() {
        RestResponse res = RestContext.response;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());
            String phone = (String) body.get('phone');
            String email = (String) body.get('email');
            Map<String, Object> data = AgentCustomerService.lookupCustomer(phone, email);
            AgentApiResponse.writeSuccess(res, data);
        } catch (AgentApiException e) {
            AgentApiResponse.writeError(res, 400, e.getMessage(), 'BAD_REQUEST');
        } catch (Exception e) {
            AgentApiResponse.writeError(res, 500, 'Unexpected error: ' + e.getMessage(), 'INTERNAL_ERROR');
        }
    }
}
