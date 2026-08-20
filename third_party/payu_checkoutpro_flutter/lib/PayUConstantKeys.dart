class PayUConstants {
  static const payUPaymentParams = "payUPaymentParams";
  static const payUCheckoutProConfig = "payUCheckoutProConfig";
  //Callback handling, Method channel name
  static const onPaymentSuccess = "onPaymentSuccess";
  static const onPaymentFailure = "onPaymentFailure";
  static const onPaymentCancel = "onPaymentCancel";
  static const onError = "onError";
  static const generateHash = "generateHash";
  static const errorMsg = "errorMsg";
  static const errorCode = "errorCode";
  static const isTxnInitiated = "isTxnInitiated";
}

class PayUHashConstantsKeys {
  static const hashName = "hashName";
  static const hashString = "hashString";
  static const hashType = "hashType";
  static const hashVersionV1 = "V1";
  static const hashVersionV2 = "V2";
  static const mcpLookup = "mcpLookup";
  static const postSalt = "postSalt";
}

//Payment request keys ------
class PayUPaymentParamKey {
  static const key = "key";
  static const amount = "amount";
  static const productInfo = "productInfo";
  static const firstName = "firstName";
  static const email = "email";
  static const phone = "phone";
  static const ios_surl = "ios_surl";
  static const ios_furl = "ios_furl";
  static const android_surl = "android_surl";
  static const android_furl = "android_furl";
  static const environment = "environment";
  static const userCredential = "userCredential";
  static const transactionId = "transactionId";
  static const additionalParam = "additionalParam";
  static const payUSIParams = "payUSIParams";
  static const splitPaymentDetails = "splitPaymentDetails";
  static const enableNativeOTP = "enableNativeOTP";
  static const userToken = "userToken"; //Offers user token -
  static const skuDetails = "skuDetails";
  static const beneficiaryDetails = "beneficiaryDetails"; //TPV
  static const additionalCharges = "additionalCharges";
  static const percentageAdditionalCharges = "percentageAdditionalCharges"; //
  static const enforcementOfferKeys = "enforcementOfferKeys"; // EnforceOffers
  static const products = "products"; // Weltech Product
  static const address = "address"; // OPSG Merchant
}

class PayUSIParamsKeys {
  static const isPreAuthTxn = "isPreAuthTxn";
  static const isFreeTrial = "isFreeTrial";
  static const billingAmount = "billingAmount";
  static const billingInterval = "billingInterval";
  static const paymentStartDate = "paymentStartDate";
  static const paymentEndDate = "paymentEndDate";
  static const billingCycle = "billingCycle";
  static const remarks = "remarks";
  static const billingCurrency = "billingCurrency";
  static const billingLimit = "billingLimit";
  static const billingRule = "billingRule";
}

class PayUAdditionalParamKeys {
  static const udf1 = "udf1";
  static const udf2 = "udf2";
  static const udf3 = "udf3";
  static const udf4 = "udf4";
  static const udf5 = "udf5";
  static const merchantAccessKey = "merchantAccessKey";
  static const sourceId = "sourceId"; //Sodexo source ID
  static const walletUrn = "walletUrn";
}

class PayUSKUKeys {
  static const skus = "skus";
  static const skuId = "skuId";
  static const skuName = "skuName";
  static const quantity = "quantity";
  static const skuAmount = "skuAmount";
  static const offerKeys = "offerKeys";
}

class PayUBeneficiaryKeys {
  static const beneficiaryAccount = "beneficiaryAccount";
  static const beneficiaryIfsc = "beneficiaryIfsc";
  static const beneficiaryName = "beneficiaryName";
  static const beneficiaryAccountType = "beneficiaryAccountType";
  static const verificationMode = "verificationMode";
}

class PayUAddressKeys {
  static const lastName = "lastName";
  static const address1 = "address1";
  static const address2 = "address2";
  static const city = "city";
  static const state = "state";
  static const country = "country";
  static const zipcode = "zipcode";
}

class PayUWealthTechKeys {
  static const type = "type";
  static const amount = "amount";
  static const receipt = "receipt";
  static const plan = "plan";
  static const folio = "folio";
  static const option = "option";
  static const scheme = "scheme";

  static const mfMemberID = "mfMemberID";
  static const mfUserID = "mfUserID";
  static const mfPartner = "mfPartner";
  static const mfInvestmentType = "mfInvestmentType";
  static const mfAMCCode = "mfAMCCode";
}

class PayUCheckoutProConfigKeys {
  static const primaryColor = "primaryColor";
  static const secondaryColor = "secondaryColor";
  static const merchantName = "merchantName";
  static const merchantLogo = "merchantLogo";
  static const showExitConfirmationOnCheckoutScreen =
      "showExitConfirmationOnCheckoutScreen";
  static const showExitConfirmationOnPaymentScreen =
      "showExitConfirmationOnPaymentScreen";
  static const cartDetails = "cartDetails";
  static const paymentModesOrder = "paymentModesOrder";
  static const merchantResponseTimeout = "merchantResponseTimeout";
  static const customNotes = "customNotes";
  static const autoSelectOtp = "autoSelectOtp";
  static const enforcePaymentList = "enforcePaymentList";

  static const waitingTime = "waitingTime"; //-->(Android)
  static const autoApprove = "autoApprove"; //-->(Android)
  static const merchantSMSPermission = "merchantSMSPermission"; //-->(Android)
  static const showCbToolbar = "showCbToolbar"; //-->(Android)
  static const showMerchantLogo = "showMerchantLogo"; //-->(Android)
  static const enableSavedCard = "enableSavedCard"; //-->(Android)
  static const enableSslDialog = "enableSslDialog"; //-->(Android)
  static const baseTextColor = "baseTextColor"; //-->(Android)
  static const enableREOptions = "enableREOptions"; //-->(Android)
  static const isProtectedScreen = "isProtectedScreen";
  static const upiAppsOrder = "upiAppsOrder";
}


class PayUPaymentTypeKeys {
  
   static const card =  "CARD";
   static const nb =  "NB";
   static const upi =  "UPI";
   static const upiIntent =  "UPI_INTENT";
   static const wallet =  "WALLET";
   static const emi =  "EMI";
   static const neftRtgs =  "NEFTRTGS";
   static const l1Option =  "L1_OPTION";
   static const sodexo =  "SODEXO";
}
