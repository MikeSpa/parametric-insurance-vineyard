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

    uint256 public constant SECONDS_IN_A_DAY = 60; // testing!! TODO = 1 days;
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

    // #############  ORACLES  #################3
    // bytes32 public jobId;
    bytes32 public jobId_accu;
    // address public oracle;
    address public oracle_accu;

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

    /// @notice Constructor
    /// @param _client the address of the client
    /// @param _duration the duration of the contract in seconds
    /// @param _premium the premium amount in USD * 100_000_000
    /// @param _payoutValue the payout amount in USD * 100_000_000
    /// @param _vineyardLocation the vineyard location
    /// @param _link the LINK address
    /// @param _oraclePaymentAmount amount of LINK paid to the oracle (0.1 LINK)
    constructor(
        address _client,
        uint256 _duration,
        uint256 _premium,
        uint256 _payoutValue,
        string memory _vineyardLocation,
        address _link,
        uint256 _oraclePaymentAmount,
        address eth_usd_price_feed
    ) payable Ownable() {
        priceFeed = AggregatorV3Interface(eth_usd_price_feed);

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

        // oracle = 0xCC79157eb46F5624204f47AB42b3906cAA40eaB7;
        oracle_accu = 0xB9756312523826A566e222a34793E414A81c88E1;
        // jobId = "ca98366cc7314957b8c012c72f05aeeb"; // uint256
        jobId_accu = "0ef6e60880e24cb69cb99a1cad76f15a"; // bytes32

        emit contractCreated(insurer, client, duration, premium, payoutValue);
    }

    // ###############  FUNCTIONS  ###############################

    /// @notice Update the contract
    function updateContract()
        public
        onContractActive
    // returns (bytes32 requestId)
    {
        checkEndContract();

        //contract may have been marked inactive above, only do request if needed
        if (contractActive) {
            checkRainfall(oracle_accu, jobId_accu);
        }
    }

    /// @notice Send a request to an oracle to get the rainfall
    /// @param _oracle the address of the oracle
    /// @param _jobId the job id
    /// @return requestId the request id
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

    /// @notice Callback function
    /// @param _requestId the request id
    /// @param _currentConditionsResult the current condition
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
    /// @notice Pay the client
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

    /// @notice Check if the contract has expired TODO
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

    /// @notice Return the price from the ETH/USD pricefeed
    /// @return int256 the price of ETH/USD
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
