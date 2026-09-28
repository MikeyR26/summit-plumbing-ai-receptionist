@RestResource(urlMapping='/agent/v1/createCustomer')
global with sharing class AgentCreateCustomerResource {
    @HttpPost
    global static void createCustomer() {
        RestResponse res = RestContext.response;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());
            Map<String, Object> data = AgentCustomerService.createCustomer(
                (String) body.get('firstName'),
                (String) body.get('lastName'),
                (String) body.get('phone'),
                (String) body.get('email'),
                (String) body.get('street'),
                (String) body.get('city'),
                (String) body.get('postalCode')
            );
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
