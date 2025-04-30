public with sharing class CibilAgentforceAction {
    // JSON shape from Beeceptor
    private class CibilResponse {
        public String pan;
        public Integer cibilScore;
        public String scoreBand;
    }

    // Input wrapper for Agentforce
    public class RequestWrapper {
        @InvocableVariable(label='PAN Number' required=true)
        public String panNumber;
    }

    // Output wrapper for Agentforce
    public class ResponseWrapper {
        @InvocableVariable(label='Result Message')
        public String result;
    }

    @InvocableMethod(label='Get CIBIL Score for PAN')
    public static List<ResponseWrapper> getCibilScore(List<RequestWrapper> requests) {
        List<ResponseWrapper> results = new List<ResponseWrapper>();
        
        for (RequestWrapper reqItem : requests) {
            ResponseWrapper resItem = new ResponseWrapper();
            try {
                // Perform the HTTP callout to your Beeceptor mock
                HttpRequest httpReq = new HttpRequest();
                httpReq.setEndpoint(
                    'callout:CIBIL_API/api/cibil-score?pan=' 
                    + EncodingUtil.urlEncode(reqItem.panNumber, 'UTF-8')
                );
                httpReq.setMethod('GET');
                HttpResponse httpRes = new Http().send(httpReq);

                if (httpRes.getStatusCode() == 200) {
                    // Deserialize the returned JSON
                    CibilResponse cr = (CibilResponse) JSON.deserialize(
                        httpRes.getBody(), CibilResponse.class
                    );
                    Integer score = cr.cibilScore;
                    // Compute the band
                    String band;
                    if (score < 550) {
                        band = 'Poor';
                    } else if (score < 650) {
                        band = 'Fair';
                    } else if (score < 750) {
                        band = 'Average';
                    } else {
                        band = 'Good';
                    }
                    // Build the result message
                    resItem.result = 'CIBIL Score for PAN ' 
                                     + reqItem.panNumber 
                                     + ' is ' 
                                     + score 
                                     + ' (' 
                                     + band 
                                     + ')';
                } else {
                    resItem.result = 'Error: CIBIL API returned status ' 
                                     + httpRes.getStatusCode();
                }
            } catch (Exception ex) {
                resItem.result = 'Exception: ' + ex.getMessage();
            }
            results.add(resItem);
        }
        return results;
    }
}