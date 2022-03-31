pragma solidity >=0.5.0 <0.7.0;


import "../../interface/IERC20.sol";
import "../../common/AddressResolver.sol";
import "../interface/IFoundry.sol";
import "../interface/IFoundryExtend.sol";
import "../interface/ICombo.sol";
import "../interface/IKPToken.sol";
import "../interface/IFeePool.sol";
import "../interface/IPrivatePlacement.sol";
import "../interface/IExchangeRates.sol";
import "../interface/IRewardEscrow.sol";
import "../interface/IRewardDistribution.sol";
import "../interface/IKPTMortgage.sol";
import "../interface/IKPTMinter.sol";
import "../interface/IRelationship.sol";
import "../interface/IProxyFee.sol";



contract MixinResolver is AddressResolver {

    function kpToken() public view returns (IKPToken) {
        return IKPToken(resolver().addr("KPToken", "MixinResolver: missing kpToken address"));
    }

    function usdt() public view returns (IERC20) {
        return IERC20(resolver().addr("USDT", "MixinResolver: missing usdt address"));
    }

    function kptMinter() public view returns (IKPTMinter) {
        return IKPTMinter(resolver().addr("KPTMinter", "MixinResolver: missing kptMinter address"));
    }

    function foundry() public view returns (IFoundry) {
        return IFoundry(resolver().addr("Foundry", "MixinResolver: missing foundry address"));
    }

    function foundryExtend() public view returns (IFoundryExtend) {
        return IFoundryExtend(resolver().addr("FoundryExtend", "MixinResolver: missing foundry-extend address"));
    }

    function kusd() public view returns (ICombo) {
        return ICombo(resolver().addr("KUSD", "MixinResolver: missing usdk address"));
    }

    function feePool() public view returns (IFeePool) {
        return IFeePool(resolver().addr("FeePool", "MixinResolver: missing fee-pool address"));
    }

    function rates() public view returns (IExchangeRates) {
        return IExchangeRates(resolver().addr("ExchangeRates", "MixinResolver: missing exchange-rates address"));
    }

    function reward() public view returns (IRewardEscrow) {
        return IRewardEscrow(resolver().addr("RewardEscrow", "MixinResolver: missing reward-escrow address"));
    }

    function distribution() public view returns (IRewardDistribution) {
        return IRewardDistribution(resolver().addr("RewardDistribution", "MixinResolver: missing reward-distribution address"));
    }

    function privatePlacement() public view returns (IPrivatePlacement) {
        return IPrivatePlacement(resolver().addr("PrivatePlacement", "MixinResolver: missing privatePlacement address"));
    }

    function mortgage() public view returns (IKPTMortgage) {
        return IKPTMortgage(resolver().addr("Mortgage", "MixinResolver: missing mortgage address"));
    }

    function relationship() public view returns (IRelationship) {
        return IRelationship(resolver().addr("Relationship", "MixinResolver: missing Relationship address"));
    }

    function proxyFee() public view returns (IProxyFee) {
        return IProxyFee(resolver().addr("ProxyFee", "MixinResolver: missing ProxyFee address"));
    }

}