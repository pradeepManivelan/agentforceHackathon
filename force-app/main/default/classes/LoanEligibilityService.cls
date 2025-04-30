public class LoanEligibilityService {
    // Credit score mapping
    private static final Map<String, Integer> CREDIT_SCORE_MAP = new Map<String, Integer>{
        'POOR' => 500,
        'FAIR' => 600,
        'GOOD' => 700,
        'EXCELLENT' => 800
    };
    
    // Employment status weight
    private static final Map<String, Decimal> EMPLOYMENT_STATUS_WEIGHT = new Map<String, Decimal>{
        'NOT EMPLOYED' => 0.0,
        'PART TIME' => 0.7,
        'FULL TIME' => 1.0
    };
    
    /**
     * Main method to calculate loan eligibility score
     * This method is annotated with @AuraEnabled so it can be called from Agentforce
     */
    @AuraEnabled
    public static LoanEligibilityResult calculateEligibility(
        Decimal annualIncome,
        Decimal existingDebtPerMonth,
        String creditScore,
        String employmentStatus,
        Decimal loanAmount,
        String panNumber
    ) {
        LoanEligibilityResult result = new LoanEligibilityResult();
        
        try {
            // Validate inputs
            if (annualIncome <= 0) {
                throw new LoanEligibilityException('Annual income must be greater than zero');
            }
            
            if (existingDebtPerMonth < 0) {
                throw new LoanEligibilityException('Existing debt cannot be negative');
            }
            
            if (loanAmount <= 0) {
                throw new LoanEligibilityException('Loan amount must be greater than zero');
            }
            
            if (employmentStatus == null || !EMPLOYMENT_STATUS_WEIGHT.containsKey(employmentStatus.toUpperCase())) {
                throw new LoanEligibilityException('Invalid employment status');
            }
            
            // Get credit score (from parameter or API)
            Integer creditScoreValue;
            if (creditScore == null || creditScore.trim() == '') {
                if (panNumber == null || panNumber.trim() == '') {
                    throw new LoanEligibilityException('PAN number required for credit check when credit score is not provided');
                }
                
                // Get credit score from API
                CreditScoreService.CreditScoreResult creditResult = CreditScoreService.getCreditScore(panNumber);
                if (!creditResult.success) {
                    throw new LoanEligibilityException('Failed to retrieve credit score: ' + creditResult.errorMessage);
                }
                
                creditScoreValue = creditResult.scoreValue;
                result.creditScoreCategory = creditResult.scoreCategory;
            } else {
                // Use provided credit score
                if (CREDIT_SCORE_MAP.containsKey(creditScore.toUpperCase())) {
                    creditScoreValue = CREDIT_SCORE_MAP.get(creditScore.toUpperCase());
                    result.creditScoreCategory = creditScore.toUpperCase();
                } else {
                    try {
                        // Try parsing as direct number
                        creditScoreValue = Integer.valueOf(creditScore);
                        // Determine category
                        if (creditScoreValue < 550) result.creditScoreCategory = 'POOR';
                        else if (creditScoreValue < 650) result.creditScoreCategory = 'FAIR';
                        else if (creditScoreValue < 750) result.creditScoreCategory = 'GOOD';
                        else result.creditScoreCategory = 'EXCELLENT';
                    } catch (Exception e) {
                        throw new LoanEligibilityException('Invalid credit score format');
                    }
                }
            }
            
            // Calculate debt-to-income ratio
            Decimal monthlyIncome = annualIncome / 12;
            Decimal debtToIncomeRatio = (existingDebtPerMonth / monthlyIncome) * 100;
            result.debtToIncomeRatio = debtToIncomeRatio;
            
            // Check immediate disqualifiers
            if (debtToIncomeRatio > 65) {
                result.eligibilityScore = 0;
                result.reason = 'Debt-to-income ratio exceeds 65%';
                return result;
            }
            
            if (creditScoreValue < 600 && loanAmount > 1000000) {
                result.eligibilityScore = 15; // Very low eligibility
                result.reason = 'Credit score too low for requested loan amount';
                return result;
            }
            
            if (EMPLOYMENT_STATUS_WEIGHT.get(employmentStatus.toUpperCase()) == 0) {
                result.eligibilityScore = 0;
                result.reason = 'Unemployed applicants are not eligible';
                return result;
            }
            
            // Verify affordability over 10 years
            Decimal maxMonthlyPayment = (monthlyIncome * 0.35) - existingDebtPerMonth; // 35% of income minus existing debt
            Decimal monthlyLoanPaymentAt10Years = calculateMonthlyPayment(loanAmount, 10 * 12, 0.08); // Assuming 8% interest
            Decimal futureIncome = annualIncome * 1.1; // 10% increase in income
            Decimal futureMonthlyIncome = futureIncome / 12;
            Decimal futureMaxMonthlyPayment = (futureMonthlyIncome * 0.35) - existingDebtPerMonth;
            
            if (monthlyLoanPaymentAt10Years > futureMaxMonthlyPayment) {
                result.eligibilityScore = 20; // Very low eligibility
                result.reason = 'Loan amount too high to be paid within 10 years even with 10% income growth';
                return result;
            }
            
            // Progressive scoring based on factors
            // 1. Credit Score: 0-30 points
            Decimal creditScorePoints = 0;
            if (creditScoreValue < 550) creditScorePoints = 0;
            else if (creditScoreValue < 650) creditScorePoints = 15;
            else if (creditScoreValue < 750) creditScorePoints = 25;
            else creditScorePoints = 30;
            
            // 2. Debt-to-Income Ratio: 0-30 points
            Decimal dtiPoints = 0;
            if (debtToIncomeRatio > 55) dtiPoints = 5;
            else if (debtToIncomeRatio > 45) dtiPoints = 15;
            else if (debtToIncomeRatio > 35) dtiPoints = 20;
            else if (debtToIncomeRatio > 25) dtiPoints = 25;
            else dtiPoints = 30;
            
            // 3. Employment Status: 0-20 points
            Decimal employmentPoints = 20 * EMPLOYMENT_STATUS_WEIGHT.get(employmentStatus.toUpperCase());
            
            // 4. Loan Affordability: 0-20 points
            Decimal affordabilityRatio = monthlyLoanPaymentAt10Years / maxMonthlyPayment;
            Decimal affordabilityPoints = 0;
            
            if (affordabilityRatio > 1) affordabilityPoints = 0;
            else if (affordabilityRatio > 0.8) affordabilityPoints = 5;
            else if (affordabilityRatio > 0.6) affordabilityPoints = 10;
            else if (affordabilityRatio > 0.4) affordabilityPoints = 15;
            else affordabilityPoints = 20;
            
            // Calculate total eligibility score
            Decimal totalScore = creditScorePoints + dtiPoints + employmentPoints + affordabilityPoints;
            
            // Final adjustments based on specific scenarios
            if (creditScoreValue >= 750 && debtToIncomeRatio < 30 && 
                EMPLOYMENT_STATUS_WEIGHT.get(employmentStatus.toUpperCase()) == 1.0) {
                totalScore = Math.min(100, totalScore + 10); // Bonus for excellent credit + low DTI + full-time
            }
            
            if (creditScoreValue < 600 && loanAmount <= 500000) {
                totalScore = Math.min(100, totalScore + 15); // Small loan amount helps offset poor credit
            }
            
            // Set result values
            result.eligibilityScore = totalScore.intValue();
            result.creditScoreValue = creditScoreValue;
            
            // Set recommendation based on score
            if (totalScore >= 80) {
                result.recommendation = 'Highly eligible for loan';
            } else if (totalScore >= 60) {
                result.recommendation = 'Eligible for loan with standard terms';
            } else if (totalScore >= 40) {
                result.recommendation = 'Eligible for loan with higher interest rate';
            } else if (totalScore >= 20) {
                result.recommendation = 'May be eligible for reduced loan amount';
            } else {
                result.recommendation = 'Not recommended for loan approval';
            }
            
            return result;
            
        } catch (LoanEligibilityException e) {
            result.eligibilityScore = 0;
            result.reason = e.getMessage();
            return result;
        } catch (Exception e) {
            result.eligibilityScore = 0;
            result.reason = 'Error calculating eligibility: ' + e.getMessage();
            return result;
        }
    }
    
    /**
     * Method to update a Lead with eligibility results
     */
    @AuraEnabled
    public static LoanEligibilityResult updateLeadEligibility(
        Id leadId,
        Decimal annualIncome,
        Decimal existingDebtPerMonth,
        String creditScore,
        String employmentStatus,
        Decimal loanAmount,
        String panNumber
    ) {
        LoanEligibilityResult result = calculateEligibility(
            annualIncome, 
            existingDebtPerMonth, 
            creditScore, 
            employmentStatus, 
            loanAmount, 
            panNumber
        );
        
        try {
            // Update lead with eligibility results
            Lead ld = new Lead(Id = leadId);
            ld.Eligibility_Score__c = result.eligibilityScore;
            
            // If we generated the credit score, store it
            if (String.isBlank(creditScore) && !String.isBlank(result.creditScoreCategory)) {
                ld.Credit_Score__c = result.creditScoreCategory;
            }
            
            ld.Debt_To_Income_Ratio__c = result.debtToIncomeRatio;
            ld.Eligibility_Reason__c = result.reason;
            ld.Eligibility_Recommendation__c = result.recommendation;
            
            update ld;
            result.leadUpdated = true;
        } catch (Exception e) {
            result.leadUpdated = false;
            result.leadUpdateError = e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Calculate monthly payment for a loan
     */
	private static Decimal calculateMonthlyPayment(Decimal principal, Integer termInMonths, Decimal annualInterestRate) {
        // Convert to Double for Math.pow operations
        Double monthlyRate = annualInterestRate.doubleValue() / 12;
        Double principalDbl = principal.doubleValue();
        
        // Calculate using Math.pow
        Double factor = Math.pow(1 + monthlyRate, termInMonths);
        Double payment = principalDbl * (monthlyRate * factor) / (factor - 1);
        
        // Convert back to Decimal for financial precision
        return Decimal.valueOf(payment);
	}
    
    /**
     * Result class to hold eligibility details
     */
    public class LoanEligibilityResult {
        @AuraEnabled public Integer eligibilityScore { get; set; }
        @AuraEnabled public String reason { get; set; }
        @AuraEnabled public String recommendation { get; set; }
        @AuraEnabled public String creditScoreCategory { get; set; }
        @AuraEnabled public Integer creditScoreValue { get; set; }
        @AuraEnabled public Decimal debtToIncomeRatio { get; set; }
        @AuraEnabled public Boolean leadUpdated { get; set; }
        @AuraEnabled public String leadUpdateError { get; set; }
        
        public LoanEligibilityResult() {
            this.eligibilityScore = 0;
            this.reason = '';
            this.recommendation = '';
            this.creditScoreValue = 0;
            this.leadUpdated = false;
        }
    }
    
    /**
     * Custom exception class
     */
    public class LoanEligibilityException extends Exception {}
}