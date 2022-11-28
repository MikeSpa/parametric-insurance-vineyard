from scripts.helpful_scripts import POINT_ONE, ONE, TEN, get_account, get_contract
from brownie import InsuranceProvider, InsuranceContract, network, Contract


PROVIDER_FUNDING = POINT_ONE / 10
PREMIUM = POINT_ONE / 100
PAYOUT = PREMIUM * 2


def deploy_InsuranceProvider():
    account = get_account()
    pricefeed = get_contract("eth_usd_price_feed")
    link = get_contract("LINK")
    provider = InsuranceProvider.deploy(
        pricefeed,
        link,
        {"from": account, "value": PROVIDER_FUNDING},
    )
    link.transfer(provider, ONE, {"from": account})
    return provider


def deploy_InsuranceContract(provider, client, duration, premium, payout, location):
    account = get_account()

    pricefeed = get_contract("eth_usd_price_feed")
    tx = provider.newContract(
        client,
        duration,
        premium,
        payout,
        location,
        pricefeed,
        {"from": account, "value": payout},
    )

    return tx.return_value


def main():
    print(network.show_active())
    account = get_account()
    provider = deploy_InsuranceProvider()
    link = get_contract("LINK")
    print(f"Provider ETH balance: {provider.balance()/10**18}")
    print(f"Provider LINK balance: {link.balanceOf(provider)/10**18}")

    contract_addr = deploy_InsuranceContract(
        provider, account, 300, PREMIUM, PAYOUT, ""
    )  # 300 = 5 day at 60sec per day
    contract = Contract.from_abi(
        InsuranceContract._name, contract_addr, InsuranceContract.abi
    )

    print(f"Provider ETH balance: {provider.balance()/10**18}")
    print(f"Provider LINK balance: {link.balanceOf(provider)/10**18}")
    print(f"Contract ETH balance: {contract.balance()/10**18}")
    print(f"Contract LINK balance: {link.balanceOf(contract)/10**18}")

    # Request

    contract.updateContract(
        {"from": account}
    )  # TODO link not ERC20 need to mock linktoken better

    ## WITHDRAW
    provider.withdraw({"from": account})
    print(f"Provider ETH balance: {provider.balance()/10**18}")
    print(f"Provider LINK balance: {link.balanceOf(provider)/10**18}")
