from brownie import network, accounts, config, MockV3Aggregator, Contract, MockERC20
from web3 import Web3

FORKED_LOCAL_ENVIRNOMENT = ["mainnet-fork", "mainnet-fork2"]
LOCAL_BLOCKCHAIN_ENVIRONMENTS = ["development", "ganache-local", "hardhat"]

CENT = Web3.toWei(100, "ether")
POINT_ONE = Web3.toWei(0.1, "ether")
TEN = Web3.toWei(10, "ether")
ONE = Web3.toWei(1, "ether")

DECIMALS = 18
INITIAL_PRICE_FEED_VALUE = 1 * 10 ** 18


def get_account(index=None, id=None, user=None):
    if user == 1:
        accounts.add(config["wallets"]["from_key_user"])
    if index:
        return accounts[index]
    if id:
        return accounts.load(id)
    if (
        network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS
        or network.show_active() in FORKED_LOCAL_ENVIRNOMENT
    ):
        return accounts[0]
    if id:
        return accounts.load(id)
    return accounts.add(config["wallets"]["from_key"])


def get_verify_status():
    verify = (
        config["networks"][network.show_active()]["verify"]
        if config["networks"][network.show_active()].get("verify")
        else False
    )
    return verify


contract_to_mock = {
    "eth_usd_price_feed": MockV3Aggregator,
    "LINK": MockERC20,
}


def get_contract(contract_name):
    """
    This script will either:
            - Get an address from the config
            - Or deploy a mock to use for a network that doesn't have it
        Args:
            contract_name (string): This is the name that is refered to in the
            brownie config and 'contract_to_mock' variable.
        Returns:
            brownie.network.contract.ProjectContract: The most recently deployed
            Contract of the type specificed by the dictonary. This could be either
            a mock or the 'real' contract on a live network.
    """
    contract_type = contract_to_mock[contract_name]
    if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        if len(contract_type) <= 0:
            deploy_mocks()
        contract = contract_type[-1]

    else:
        try:
            contract_address = config["networks"][network.show_active()][contract_name]
            contract = Contract.from_abi(
                contract_type._name, contract_address, contract_type.abi
            )
        except KeyError:
            print(
                f"{network.show_active()} address not found, perhaps you should add it to the config or deploy mocks?"
            )
    return contract


def deploy_mocks():
    account = get_account()
    print(f"### The active netwok is {network.show_active()}")
    print("### Deploying Mocks...")
    mock_price_feed = MockV3Aggregator.deploy(
        DECIMALS, INITIAL_PRICE_FEED_VALUE, {"from": account}
    )
    print(f"MockV3Aggregator deployed to {mock_price_feed}")

    mock_link_token = MockERC20.deploy({"from": account})
    print(f"MockLINK deployed to {mock_link_token.address}")


def main():
    pass
