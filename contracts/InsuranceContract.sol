// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/Chainlink.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

contract InsuranceContract is Ownable, ChainlinkClient {
    //ETH/USD pricefeed
    AggregatorV3Interface internal priceFeed;

    address LINK_ADDRESS = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;

    uint256 public constant SECONDS_IN_A_DAY = 1 days;
    uint256 public constant DROUGHT_DAYS_THRESDHOLD = 3; //Number of consecutive days without rainfall to be defined as a drought
    uint256 private oraclePaymentAmount;

    // contract variables
    address payable public insurer;
    address payable public client;
    uint256 startDate;
    uint256 duration;
    uint256 premium;
    uint256 payoutValue;
    string vineyardLocation;

    // ########### STATE VARIABLES ######################3
    uint256 daysWithoutRain;
    bool contractActive;
    bool contractPaid = false;
    uint256 public currentRainfall = 0;
    uint256 currentRainfallDateChecked = block.timestamp; //when the last rainfall check was performed
    uint256 public requestCount = 0;
    // uint256 dataRequestsSent = 0; //variable used to determine if both requests have been sent or not

    // #############  ORACLES  #################3
    // uint256[2] public currentRainfallList;
    bytes32 public jobId;
    bytes32 public jobId_accu;
    address public oracle;
    address public oracle_accu;

    string constant WORLD_WEATHER_ONLINE_URL =
        "http://api.worldweatheronline.com/premium/v1/weather.ashx?";
    string constant WORLD_WEATHER_ONLINE_KEY = "629c6dd09bbc4364b7a33810200911";
    string constant WORLD_WEATHER_ONLINE_PATH =
        "data.current_condition.0.precipMM";

    string constant ACCU_WEATHER_ONLINE_URL =
        "http://api.worldweatheronline.com/premium/v1/weather.ashx?";
    string constant ACCU_WEATHER_ONLINE_KEY = "629c6dd09bbc4364b7a33810200911";
    string constant ACCU_WEATHER_ONLINE_PATH =
        "data.current_condition.0.precipMM";

    // ############ EVENTS  #########################

    event contractCreated(
        address _insurer,
        address _client,
        uint256 _duration,
        uint256 _premium,
        uint256 _totalCover
    );
    event contractPaidOut(
        uint256 _paidTime,
        uint256 _totalPaid,
        uint256 _finalRainfall
    );
    event contractEnded(uint256 _endTime, uint256 _totalReturned);
    event ranfallThresholdReset(uint256 _rainfall);
    event dataRequestSent(bytes32 requestId);
    event dataReceived(uint256 _rainfall);

    struct CurrentConditionsResult {
        uint256 timestamp;
        uint24 precipitationPast12Hours;
        uint24 precipitationPast24Hours;
        uint24 precipitationPastHour;
        uint24 pressure;
        int16 temperature;
        uint16 windDirectionDegrees;
        uint16 windSpeed;
        uint8 precipitationType;
        uint8 relativeHumidity;
        uint8 uvIndex;
        uint8 weatherIcon;
    }

    // ####################  MODIFIER  ##################

    // modifier onlyOwner() override {
    //     require(insurer == msg.sender, "Only Insurance provider can do this");
    //     _;
    // }

    modifier onContractActive() {
        require(
            contractActive == true,
            "Contract has ended, cant interact with it anymore"
        );
        _;
    }

    modifier onContractEnded() {
        if (startDate + duration < block.timestamp) {
            _;
        }
    }

    modifier callFrequencyOncePerDay() {
        require(
            block.timestamp - (currentRainfallDateChecked) >
                (SECONDS_IN_A_DAY - (SECONDS_IN_A_DAY / 12)),
            "Can only check rainfall once per day"
        );
        _;
    }

    //  ############### CONSTRUCTOR  ###################
    constructor(
        address _client,
        uint256 _duration,
        uint256 _premium,
        uint256 _payoutValue,
        string memory _vineyardLocation,
        address _link,
        uint256 _oraclePaymentAmount
    ) payable Ownable() {
        priceFeed = AggregatorV3Interface(
            0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
        );

        //initialize variables required for Chainlink Network interaction
        setChainlinkToken(_link);
        oraclePaymentAmount = _oraclePaymentAmount;

        //first ensure insurer has fully funded the contract
        require(
            msg.value >= _payoutValue / uint256(getLatestPrice()),
            "Not enough funds sent to contract"
        );

        //now initialize values for the contract
        insurer = payable(msg.sender);
        client = payable(_client);
        startDate = block.timestamp; //contract will be effective immediately on creation
        duration = _duration;
        premium = _premium;
        payoutValue = _payoutValue;
        daysWithoutRain = 0;
        contractActive = true;
        vineyardLocation = _vineyardLocation;

        oracle = 0xCC79157eb46F5624204f47AB42b3906cAA40eaB7;
        oracle_accu = 0xB9756312523826A566e222a34793E414A81c88E1;
        jobId = "ca98366cc7314957b8c012c72f05aeeb"; // uint256
        jobId_accu = "0ef6e60880e24cb69cb99a1cad76f15a"; // bytes32

        emit contractCreated(insurer, client, duration, premium, payoutValue);
    }

    // ###############  FUNCTIONS  ###############################

    function updateContract()
        public
        onContractActive
        returns (bytes32 requestId)
    {
        checkEndContract();

        //contract may have been marked inactive above, only do request if needed
        if (contractActive) {
            checkRainfall(oracle, jobId);
        }
    }

    function checkRainfall(address _oracle, bytes32 _jobId)
        private
        onContractActive
        returns (bytes32 requestId)
    {
        // Request:
        // The client contract that initiates this cycle must create a request with the following items:
        //-The oracle address.
        //-The job ID, so the oracle knows which tasks to perform.
        //-The callback function, which the oracle sends the response to.
        Chainlink.Request memory req = buildChainlinkRequest(
            _jobId,
            address(this),
            this.checkRainfallCallBack2.selector //TODO
        );

        // Chainlink.add(req, "get", _url); //sends the GET request to the oracleTODO
        // Chainlink.add(req, "path", _path);
        // Chainlink.addInt(req, "times", 100);

        //Accu
        Chainlink.add(req, "endpoint", "current-conditions");
        string memory _locationKey = "TODO";
        Chainlink.add(req, "locationKey", _locationKey);
        Chainlink.add(req, "units", "metric");

        requestId = sendChainlinkRequestTo(_oracle, req, oraclePaymentAmount);

        emit dataRequestSent(requestId);
    }

    // function checkRainfallCallBack(bytes32 _requestId, uint256 _rainfall)
    //     public
    //     recordChainlinkFulfillment(_requestId)
    //     onContractActive
    //     callFrequencyOncePerDay
    // {
    //     currentRainfall = _rainfall;
    //     currentRainfallDateChecked = block.timestamp;
    //     requestCount += 1;

    //     // no rain
    //     if (currentRainfall == 0) {
    //         daysWithoutRain += 1;
    //     }
    //     //rain
    //     else {
    //         daysWithoutRain = 0;
    //         emit ranfallThresholdReset(currentRainfall);
    //     }
    //     // if drought -> payout
    //     if (daysWithoutRain >= DROUGHT_DAYS_THRESDHOLD) {
    //         payOutContract();
    //     }

    //     emit dataReceived(_rainfall);
    // }

    function checkRainfallCallBack2(
        bytes32 _requestId,
        bytes memory _currentConditionsResult
    )
        public
        recordChainlinkFulfillment(_requestId)
        onContractActive
        callFrequencyOncePerDay
    {
        CurrentConditionsResult memory result = abi.decode(
            _currentConditionsResult,
            (CurrentConditionsResult)
        );
        uint24 _rainfall = result.precipitationPast24Hours;
        currentRainfall = _rainfall;
        currentRainfallDateChecked = block.timestamp;
        requestCount += 1;

        // no rain
        if (currentRainfall == 0) {
            daysWithoutRain += 1;
        }
        //rain
        else {
            daysWithoutRain = 0;
            emit ranfallThresholdReset(currentRainfall);
        }
        // if drought -> payout
        if (daysWithoutRain >= DROUGHT_DAYS_THRESDHOLD) {
            payOutContract();
        }

        emit dataReceived(_rainfall);
    }

    //TODO
    function payOutContract() private onContractActive {
        //Transfer agreed amount to client
        client.transfer(address(this).balance);

        //Transfer any remaining funds (premium) back to Insurer
        LinkTokenInterface link = LinkTokenInterface(LINK_ADDRESS);
        require(
            link.transfer(insurer, link.balanceOf(address(this))),
            "Unable to transfer"
        );

        emit contractPaidOut(block.timestamp, payoutValue, currentRainfall);

        contractActive = false;
        contractPaid = true;
    }

    function checkEndContract() private onContractEnded {
        if (requestCount >= (duration / (SECONDS_IN_A_DAY) - 2)) {
            insurer.transfer(address(this).balance);
        } else {
            client.transfer(premium / (uint256(getLatestPrice())));
            insurer.transfer(address(this).balance);
        }

        LinkTokenInterface link = LinkTokenInterface(LINK_ADDRESS);
        require(
            link.transfer(insurer, link.balanceOf(address(this))),
            "Unable to transfer remaining LINK tokens"
        );

        contractActive = false;
        emit contractEnded(block.timestamp, address(this).balance);
    }

    function getLatestPrice() public view returns (int256) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        // If the round is not complete yet, timestamp is 0
        require(timeStamp > 0, "Round not complete");
        return price;
    }
}
