// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./InsuranceContract.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/Chainlink.sol";

contract InsuranceProvider {
    // ETH/USD pricefeed
    AggregatorV3Interface public priceFeed;
    address public insurer = msg.sender;

    // mapping of each created contract: addr -> InsuranceContract
    mapping(address => InsuranceContract) public individualInsuranceContracts;

    address public immutable LINK_ADDRESS; // =
    //0x326C977E6efc84E512bB9C30f76E30c160eD06FB; //address of LINK token on Goerli
    uint256 private constant ORACLE_PAYMENT = 0.1 * 10**18; // 0.1 LINK

    uint256 public constant SECONDS_IN_A_DAY = 60; // testing!! TODO = 1 days;

    event contractCreated(
        address _insuranceContract,
        uint256 _premium,
        uint256 _totalCover
    );

    /// @notice Constructor
    /// @param eth_usd_price_feed the eth/usd price feed address
    /// @param linkAddress the link token
    constructor(address eth_usd_price_feed, address linkAddress) payable {
        priceFeed = AggregatorV3Interface(eth_usd_price_feed);
        LINK_ADDRESS = linkAddress;
    }

    modifier onlyOwner() {
        require(insurer == msg.sender, "Only Insurance provider can do this");
        _;
    }

    // #########################  FUNCTIONS  #################################

    /// @notice Create new insurance contract
    /// @param _client address of the client
    /// @param _duration duration of the contract
    /// @param _premium premium paid by the client
    /// @param _payoutValue payout amount
    /// @param _vineyardLocation The location of the vineyard
    /// @return address the address of the newly created contract
    function newContract(
        address _client,
        uint256 _duration,
        uint256 _premium,
        uint256 _payoutValue,
        string memory _vineyardLocation,
        address ethUsdPriceFeed
    ) public payable onlyOwner returns (address) {
        require(
            _premium <= msg.value,
            "InsuranceProvider: not enough ETH sent"
        ); //TODO

        //create contract, send payout amount to the new contract
        InsuranceContract i = (new InsuranceContract){
            value: (_payoutValue * 1 ether) / (uint256(getLatestPrice()))
        }(
            _client,
            _duration,
            _premium,
            _payoutValue,
            _vineyardLocation,
            LINK_ADDRESS,
            ORACLE_PAYMENT,
            ethUsdPriceFeed
        );

        // store new contract
        individualInsuranceContracts[address(i)] = i;

        //fund contract with enough LINK tokens to fulfil 1 Oracle request per day, plus a small buffer
        LinkTokenInterface link = LinkTokenInterface(LINK_ADDRESS);
        bool transfer = link.transfer(
            address(i),
            ((_duration / (SECONDS_IN_A_DAY)) + 2) * ORACLE_PAYMENT
        );
        require(transfer, "InsuranceProvider: Failed to send LINK");

        //emit an event
        emit contractCreated(address(i), msg.value, _payoutValue);

        return address(i);
    }

    /// @notice Update the contract
    /// @param _contract address of the contract
    function updateContract(address _contract) external {
        InsuranceContract i = InsuranceContract(_contract);
        i.updateContract();
    }

    /// @notice Return the current rainfall
    /// @param _contract address of the contract
    /// @return uint256 the current rainfall
    function getContractRainfall(address _contract)
        external
        view
        returns (uint256)
    {
        InsuranceContract i = InsuranceContract(_contract);
        return i.currentRainfall();
    }

    /// @notice Return the number of request made by the contract
    /// @param _contract address of the contract
    /// @return uint256 the number of request
    function getContractRequestCount(address _contract)
        external
        view
        returns (uint256)
    {
        InsuranceContract i = InsuranceContract(_contract);
        return i.requestCount();
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

    //TODO only for testing
    //withdraw all ETH and LINK
    function withdraw() public onlyOwner {
        (bool sent, bytes memory data) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(sent, "Failed to send Ether");
        LinkTokenInterface link = LinkTokenInterface(LINK_ADDRESS);
        require(
            link.transfer(payable(msg.sender), link.balanceOf(address(this))),
            "Failed to send LINK"
        );
    }

    receive() external payable {}
}
