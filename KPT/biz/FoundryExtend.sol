pragma solidity >=0.5.0 <0.7.0;


import "../../library/SafeMath.sol";
import "../../common/Ownable.sol";
import "../../access/WhitelistedRole.sol";
import "./FoundryStorage.sol";
import "../common/MixinResolver.sol";
import "../interface/ICombo.sol";


contract FoundryExtend is WhitelistedRole, MixinResolver {
    using SafeMath for uint;

    FoundryStorage public foundryStorage;

    uint private UNIT = 10 ** 18;

    uint256 public lastMortgateRewardTimestamp = 0;
    uint256 public minimumRewardInterval = 20 hours;

    uint256 public rewardUpperBoundary = 100 * 10 ** 16;
    uint256 public rewardLowerBoundary = 1 * 10 ** 16;
    uint256 public rewardUpperDailyRate = 10 * 10 ** 14;
    uint256 public rewardLowerDailyRate = 5 * 10 ** 14;


    constructor()
    public
    {}

    function setFoundryStorage(FoundryStorage _foundryStorage) external onlyOwner {
        foundryStorage = _foundryStorage;
    }

    function executeMortgage(uint256 amount, address proxy) public returns (bool){
        require(relationship().verifyAndBind(msg.sender, proxy), "FoundryExtend: proxy verify failed");
        foundryStorage.recordMortgatedAccount(msg.sender);
        emit Mortgage(msg.sender, amount);
        return mortgage().mortgage(msg.sender, amount);
    }

    function executePlatMortgage(uint256 amount) public returns (bool){
        foundryStorage.recordMortgatedAccount(msg.sender);
        emit Mortgage(msg.sender, amount);
        return mortgage().mortgage(msg.sender, amount);
    }

    function lockMortgage(uint256 amount) public {
        (uint256 expire, uint256 lockAmount) = foundryStorage.getLockStatus(msg.sender);
        require(expire < now, "FoundryExtend: already lock, try again after redemption");
        require(lockAmount == 0, "FoundryExtend: locked amount remain, try again after redemption");
        uint canTransfer = transferableKPT(msg.sender);
        require(amount <= canTransfer, "FoundryExtend: usable amount not enough");
        require(mortgage().redemptionTo(msg.sender, address(this), amount), "FoundryExtend: kpt inner trasfer failed");
        foundryStorage.lockMortgage(msg.sender, amount);
        emit LockMortgage(msg.sender, amount);
    }

    function redemption(uint256 amount) public {
        (uint256 expire, uint256 lockAmount) = foundryStorage.getLockStatus(msg.sender);
        require(expire < now, "FoundryExtend: already lock, try again after expired");
        require(lockAmount > 0, "FoundryExtend: no locked amount");
        foundryStorage.unlockMortgage(msg.sender, amount);
        kpToken().transfer(msg.sender, amount);
        emit Redemption(msg.sender, amount);
    }

    function flux(address seller, address buyer, uint256 amount) external onlyFoundry {
        require(seller != address(0), "FoundryExtend: seller address can not be zero");
        require(buyer != address(0), "FoundryExtend: buyer address can not be zero");
        mortgage().innerTransfer(seller, buyer, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external onlyFoundry returns (bool) {
        require(from != address(0), "FoundryExtend: from address can not be zero");
        require(to != address(0), "FoundryExtend: to address can not be zero");
        mortgage().innerTransferFrom(from, to, amount);
        return true;
    }

    /**
     * @notice A function that lets you easily convert an amount in a source currency to an amount in the destination currency
     * @param sourceCurrencyKey The currency the amount is specified in
     * @param sourceAmount The source amount, specified in UNIT base
     * @param destinationCurrencyKey The destination currency
     */
    function effectiveValue(bytes32 sourceCurrencyKey, uint sourceAmount, bytes32 destinationCurrencyKey)
        public
        view
        returns (uint)
    {
        if (sourceCurrencyKey == destinationCurrencyKey || sourceAmount == 0) {
            return sourceAmount;
        }
        return rates().ratio(sourceCurrencyKey, sourceAmount, destinationCurrencyKey);
    }

    function setMinimumRewardInterval(uint256 interval) public onlyOwner {
        minimumRewardInterval = interval;
    }

    function mortgateReward() public onlyOwner {
        require(lastMortgateRewardTimestamp + minimumRewardInterval <= now, "Foundry: not reach the minimum inverval yet");
        address[] memory allMortgated = foundryStorage.getAllMortgated();
        uint256 payRewardAmount = _payRewardAmount(allMortgated);
        if(payRewardAmount == 0){
            emit MortgateReward(payRewardAmount, payRewardAmount);
            return;
        }
        mortgage().transferReward(payRewardAmount);
        uint256 payRewardAmountActual = _mortgateRewardIn(allMortgated);
        lastMortgateRewardTimestamp = now;
        emit MortgateReward(payRewardAmount, payRewardAmountActual);// for test
    }

    function mortgateRewardIn(address[] memory accounts) public onlyOwner {
        require(lastMortgateRewardTimestamp + minimumRewardInterval <= now, "Foundry: not reach the minimum inverval yet");
        uint256 payRewardAmount = _payRewardAmount(accounts);
        if(payRewardAmount == 0){
            emit MortgateReward(payRewardAmount, payRewardAmount);
            return;
        }
        mortgage().transferReward(payRewardAmount);
        uint256 payRewardAmountActual = _mortgateRewardIn(accounts);
        emit MortgateReward(payRewardAmount, payRewardAmountActual);// for test
    }

    function _mortgateRewardIn(address[] memory accounts) internal returns (uint256) {//return for test, is going to be deleted
        uint256 totalRewardAmount = 0;
        uint priceRatio = effectiveValue("KUSD", UNIT, "KPT");//unit * kpt price/ kusd price 
        for(uint index = 0; index < accounts.length; index ++){
            //查询质押率, 质押数量*KPT价格/债务数量*KUSD价格
            uint256 kptBalance = kptBalanceOf(accounts[index]);
            uint256 debtBalance = foundry().debtBalanceOf(accounts[index], "KUSD");
            uint256 dailyRate = 0;
            if (debtBalance == 0){
                dailyRate = rewardUpperDailyRate;
            } else {
                uint256 cRatio = kptBalance.wmulRound(priceRatio).wdivRound(debtBalance).wdivRound(UNIT);
                if (cRatio > rewardUpperBoundary) {
                    dailyRate = rewardUpperDailyRate;
                } else if (cRatio > rewardLowerBoundary){
                    dailyRate = rewardLowerDailyRate;
                } else {
                    continue;
                }
            }
            uint256 rewardAmount = kptBalance.wmulRound(dailyRate).wdivRound(UNIT);
            if (rewardAmount == 0) {
                continue;
            }
            reward().deposit(accounts[index], rewardAmount);
            totalRewardAmount.add(rewardAmount);
        }
        return totalRewardAmount;
    }

    function _payRewardAmount(address[] memory accounts) public view returns (uint256) {// public fot test 
        uint256 totalRewardAmount = 0;
        uint priceRatio = effectiveValue("KUSD", UNIT, "KPT");//unit * kpt price/ kusd price 
        for(uint index = 0; index < accounts.length; index ++){
            //查询质押率, 质押数量*KPT价格/债务数量*KUSD价格
            uint256 kptBalance = kptBalanceOf(accounts[index]);
            uint256 debtBalance = foundry().debtBalanceOf(accounts[index], "KUSD");
            uint256 dailyRate = 0;
            if (debtBalance == 0){
                dailyRate = rewardUpperDailyRate;
            } else {
                uint256 cRatio = kptBalance.wmulRound(priceRatio).wdivRound(debtBalance).wdivRound(UNIT);
                if (cRatio > rewardUpperBoundary) {
                    dailyRate = rewardUpperDailyRate;
                } else if (cRatio > rewardLowerBoundary){
                    dailyRate = rewardLowerDailyRate;
                } else {
                    continue;
                }
            }
            uint256 rewardAmount = kptBalance.wmulRound(dailyRate).wdivRound(UNIT);
            if (rewardAmount == 0) {
                continue;
            }
            totalRewardAmount = totalRewardAmount.add(rewardAmount);
        }
        return totalRewardAmount;
    }

    function withdraw() public returns (bool) {
        require(reward().withdrawable(msg.sender) > 0, "Foundry: reward is zero");
        uint256 reward = reward().withdraw(msg.sender);
        return mortgage().redemptionReward(msg.sender, reward);
    }

    function cRatio(address account) public view returns (uint256) {
        uint priceRatio = effectiveValue("KUSD", UNIT, "KPT");
        uint256 kptBalance = kptBalanceOf(account);
        uint256 debtBalance = foundry().debtBalanceOf(account, "KUSD");
        require(debtBalance > 0, "Foundry: debtBalance is zero");
        uint256 cRatio = kptBalance.wmulRound(priceRatio).wdivRound(debtBalance).wdivRound(UNIT);
        return cRatio;
    }

    function rewardAmount(address accounts)public view returns (uint256,uint256,uint256,uint256) {
        uint256 totalRewardAmount = 0;
        uint priceRatio = effectiveValue("KUSD", UNIT, "KPT");

            uint256 kptBalance = kptBalanceOf(accounts);
            uint256 debtBalance = foundry().debtBalanceOf(accounts, "KUSD");
            uint256 dailyRate = 0;
            if (debtBalance == 0){
                dailyRate = rewardUpperDailyRate;
            } else {
                uint256 cRatio = kptBalance.wmulRound(priceRatio).wdivRound(debtBalance).wdivRound(UNIT);
                if (cRatio > rewardUpperBoundary) {
                    dailyRate = rewardUpperDailyRate;
                } else if (cRatio > rewardLowerBoundary){
                    dailyRate = rewardLowerDailyRate;
                }
            }
            uint256 rewardAmount = kptBalance.wmulRound(dailyRate).wdivRound(UNIT);
        totalRewardAmount = totalRewardAmount.add(rewardAmount);
        return (totalRewardAmount,dailyRate,kptBalance,UNIT);
    }

    function transferableKPT(address account)
    public
    view
    returns (uint)
    {
        uint balance = mortgage().balanceOf(account);

        uint lockedKPTValue = foundry().debtBalanceOf(account, "KPT").wdivRound(foundryStorage.issuanceRatio());
        // If we exceed the balance, no KPT are transferable, otherwise the difference is.
        if (lockedKPTValue >= balance) {
            return 0;
        } else {
            return balance.sub(lockedKPTValue);
        }
    }

    function getUserComboDetail(address account) public view returns (uint256[2][] memory amounts, bytes32[] memory currencies) {
        uint len = foundry().getComboLength();
        amounts = new uint256[2][](len);
        currencies = new bytes32[](len);
        for (uint i = 0; i < len; i++) {
            ICombo combo = foundry().availableCombos(i);
            currencies[i] = combo.currencyKey();
            uint256 a = combo.balanceOf(account);
            amounts[i][0] = a;
            amounts[i][1] = foundry().effectiveValue(currencies[i], a, "KUSD");
        }
    }

    function getUserTotalCombos(address account) public view returns (uint256) {
        uint256 amount = 0;
        uint len = foundry().getComboLength();
        for (uint i = 0; i < len; i++) {
            ICombo combo = foundry().availableCombos(i);
            amount = amount.add(foundry().effectiveValue(combo.currencyKey(), combo.balanceOf(account), "USDK"));
        }
        return amount;
    }

    function kptBalanceOf(address account) public view returns (uint256) {
        return mortgage().balanceOf(account);
    }

    function kptBalanceOfProxy(address proxy) public view returns (uint256) {
        uint256 totalKpt = kptBalanceOf(proxy);
        address[] memory bindings = relationship().getAllProxyBindings(proxy);
        for(uint index = 0; index < bindings.length; index ++){
            totalKpt = totalKpt.add(kptBalanceOf(bindings[index]));
        }
        return totalKpt;
    }

    function payReward(uint256 amount) public onlyFoundry {
        return mortgage().transferReward(amount);
    }

    modifier onlyFoundry() {
        require(msg.sender == address(foundry()), "FoundryExtend: Only foundry allowed");
        _;
    }

    event MortgateReward(uint256 total1, uint256 total2);//for test
    event Redemption(address account, uint256 amount);
    event Mortgage(address account, uint256 amount);
    event LockMortgage(address account, uint256 amount);
}