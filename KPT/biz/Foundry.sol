pragma solidity >=0.5.0 <0.7.0;


import "../common/ExternStorage.sol";
import "../../erc20/ERC20Storage.sol";
import "../../library/Address.sol";
import "./FoundryStorage.sol";
import "../interface/ICombo.sol";
import "../interface/IRewardEscrow.sol";
import "../common/MixinResolver.sol";

/**
 * @title Foundry ERC20 contract.
 * @notice The Foundry contracts not only facilitates transfers, exchanges, and tracks balances,
 * but it also computes the quantity of fees each Foundry holder is entitled to.
 */
contract Foundry is MixinResolver, ExternStorage {
    using Address for address;

    // ========== STATE VARIABLES ==========

    // Available Synths which can be used with the system
    ICombo[] public availableCombos;
    mapping(bytes32 => ICombo) public combos;
    mapping(address => bytes32) public combosByAddress;

    FoundryStorage public foundryStorage;

    uint private UNIT = 10 ** 18;

    bool private protectionCircuit = false;

    string constant TOKEN_NAME = "Foundry Network Token";
    string constant TOKEN_SYMBOL = "custom";
    uint8 constant DECIMALS = 18;
    bool public exchangeEnabled = false;
    uint public gasPriceLimit;

    address public gasLimitOracle;

    // ========== CONSTRUCTOR ==========

    /**
     * @dev Constructor
     */
    constructor()
        ExternStorage(TOKEN_NAME, TOKEN_SYMBOL, DECIMALS)
        public
    {}
    // ========== SETTERS ========== */


    function setFoundryStorage(FoundryStorage _foundryStorage)
        external
        optionalProxyAndOnlyOwner
    {
        foundryStorage = _foundryStorage;
    }

    function setProtectionCircuit(bool _protectionCircuitIsActivated)
        external
        onlyOwner
    {
        protectionCircuit = _protectionCircuitIsActivated;
    }

    function setExchangeEnabled(bool _exchangeEnabled)
        external
        optionalProxyAndOnlyOwner
    {
        exchangeEnabled = _exchangeEnabled;
    }

    function setGasLimitOracle(address _gasLimitOracle)
        external
        optionalProxyAndOnlyOwner
    {
        gasLimitOracle = _gasLimitOracle;
    }

    function setGasPriceLimit(uint _gasPriceLimit)
        external
    {
        require(msg.sender == gasLimitOracle, "Foundry: Only gas limit oracle allowed");
        require(_gasPriceLimit > 0, "Foundry: Needs to be greater than 0");
        gasPriceLimit = _gasPriceLimit;
    }

    /**
     * @notice Add an associated Combo contract to the Foundry system
     * @dev Only the contract owner may call this.
     */
    function addCombo(ICombo combo)
        external
        optionalProxyAndOnlyOwner
    {
        bytes32 currencyKey = combo.currencyKey();
        address comboAddress = address(combo);
        require(combos[currencyKey] == ICombo(0), "Foundry: Combo already exists");
        require(combosByAddress[comboAddress] == bytes32(0), "Foundry: Combo address already exists");
        availableCombos.push(combo);
        combos[currencyKey] = combo;
        combosByAddress[comboAddress] = currencyKey;
    }

    /**
     * @notice Remove an associated Combo contract from the Foundry system
     * @dev Only the contract owner may call this.
     */
    function removeCombo(bytes32 currencyKey)
        external
        optionalProxyAndOnlyOwner
    {
        require(address(combos[currencyKey]) != address(0), "Foundry: Combo does not exist");
        require(combos[currencyKey].totalSupply() == 0, "Foundry: Combo supply exists");
        require(currencyKey != "KUSD", "Foundry: Cannot remove KUSD");

        // Save the address we're removing for emitting the event at the end.
        address comboToRemove = address(combos[currencyKey]);

        // Remove the combo from the availableCombos array.
        for (uint i = 0; i < availableCombos.length; i++) {
            if (address(availableCombos[i]) == comboToRemove) {
                delete availableCombos[i];
                availableCombos[i] = availableCombos[availableCombos.length - 1];

                // Decrease the size of the array by one.
                availableCombos.length--;

                break;
            }
        }

        // And remove it from the combos mapping
        delete combosByAddress[address(combos[currencyKey])];
        delete combos[currencyKey];

    }

    // ========== VIEWS ==========

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

    /**
     * @notice Total amount of combos issued by the system, priced in currencyKey
     * @param currencyKey The currency to value the combos in
     */
    function totalIssuedCombos(bytes32 currencyKey)
        public
        view
        returns (uint)
    {
        uint total = 0;
        uint currencyRate = rates().getFeedPrice(currencyKey);

        (uint[] memory rates, bool anyRateStale) = rates().getFeedPricesAndAnyExpired(availableCurrencyKeys());
        require(!anyRateStale, "Foundry: Rates are stale");

        for (uint i = 0; i < availableCombos.length; i++) {
            uint comboValue = availableCombos[i].totalSupply()
                .wmulRound(rates[i]);
            total = total.add(comboValue);
        }

        return total.wdivRound(currencyRate);
    }

    /**
     * @notice Returns the currencyKeys of availableCombos for rate checking
     */
    function availableCurrencyKeys()
        public
        view
        returns (bytes32[] memory)
    {
        bytes32[] memory currencyKeys = new bytes32[](availableCombos.length);

        for (uint i = 0; i < availableCombos.length; i++) {
            currencyKeys[i] = combosByAddress[address(availableCombos[i])];
        }

        return currencyKeys;
    }

    /**
     * @notice Determine the effective fee rate for the exchange, taking into considering swing trading
     */
    function feeRateForExchange(bytes32 sourceCurrencyKey, bytes32 destinationCurrencyKey)
        public
        view
        returns (uint)
    {
        // Get the base exchange fee rate
        uint exchangeFeeRate = feePool().exchangeFeeRate();
        uint multiplier = UNIT;

        return exchangeFeeRate.wmul(multiplier);
    }
    // ========== MUTATIVE FUNCTIONS ==========

    /**
     * @notice ERC20 transfer function for KPT.
     */
    function transfer(address to, uint value)
        public
        returns (bool)
    {
        foundryExtend().flux(msg.sender, to, value);
        return true;
    }

     /**
     * @notice ERC20 transferFrom function for KPT.
     */
    function transferFrom(address from, address to, uint value)
        public
        returns (bool)
    {
        return foundryExtend().transferFrom(from, to, value);
    }

    /**
     * @notice Function that allows you to exchange combos you hold in one flavour for another.
     * @param sourceCurrencyKey The source currency you wish to exchange from
     * @param sourceAmount The amount, specified in UNIT of source currency you wish to exchange
     * @param destinationCurrencyKey The destination currency you wish to obtain.
     * @return Boolean that indicates whether the transfer succeeded or failed.
     */
    function exchange(bytes32 sourceCurrencyKey, uint sourceAmount, bytes32 destinationCurrencyKey)
        external
        optionalProxy
        // Note: We don't need to insist on non-stale rates because effectiveValue will do it for us.
        returns (bool)
    {
        require(sourceCurrencyKey != destinationCurrencyKey, "Foundry: Can't be same combo");
        require(sourceAmount > 0, "Foundry: Zero amount");

        // verify gas price limit
        validateGasPrice(tx.gasprice);

        //  If the oracle has set protectionCircuit to true then burn the combos
        if (protectionCircuit) {
            combos[sourceCurrencyKey].burn(caller, sourceAmount);
            return true;
        } else {
            // Pass it along, defaulting to the sender as the recipient.
            return _internalExchange(
                caller,
                sourceCurrencyKey,
                sourceAmount,
                destinationCurrencyKey,
                caller,
                true // Charge fee on the exchange
            );
        }
    }

    /*
        @dev validate that the given gas price is less than or equal to the gas price limit
        @param _gasPrice tested gas price
    */
    function validateGasPrice(uint _givenGasPrice)
        public
        view
    {
        require(_givenGasPrice <= gasPriceLimit, "Foundry: Gas price above limit");
    }

    /**
     * @notice Function that allows combo contract to delegate exchanging of a combo that is not the same sourceCurrency
     * @dev Only the combo contract can call this function
     * @param from The address to exchange / burn combo from
     * @param sourceCurrencyKey The source currency you wish to exchange from
     * @param sourceAmount The amount, specified in UNIT of source currency you wish to exchange
     * @param destinationCurrencyKey The destination currency you wish to obtain.
     * @param destinationAddress Where the result should go.
     * @return Boolean that indicates whether the transfer succeeded or failed.
     */
    function comboInitiatedExchange(
        address from,
        bytes32 sourceCurrencyKey,
        uint sourceAmount,
        bytes32 destinationCurrencyKey,
        address destinationAddress
    )
        external
        optionalProxy
        returns (bool)
    {
        require(combosByAddress[caller] != bytes32(0), "Foundry: Only combo allowed");
        require(sourceCurrencyKey != destinationCurrencyKey, "Foundry: Can't be same combo");
        require(sourceAmount > 0, "Foundry: Zero amount");

        // Pass it along
        return _internalExchange(
            from,
            sourceCurrencyKey,
            sourceAmount,
            destinationCurrencyKey,
            destinationAddress,
            false
        );
    }

    /**
     * @notice Function that allows combo contract to delegate sending fee to the fee Pool.
     * @dev fee pool contract address is not allowed to call function
     * @param from The address to move combo from
     * @param sourceCurrencyKey source currency from.
     * @param sourceAmount The amount, specified in UNIT of source currency.
     * @param destinationCurrencyKey The destination currency to obtain.
     * @param destinationAddress Where the result should go.
     * @param chargeFee Boolean to charge a fee for exchange.
     * @return Boolean that indicates whether the transfer succeeded or failed.
     */
    function _internalExchange(
        address from,
        bytes32 sourceCurrencyKey,
        uint sourceAmount,
        bytes32 destinationCurrencyKey,
        address destinationAddress,
        bool chargeFee
    )
        internal
        returns (bool)
    {
        require(exchangeEnabled, "Foundry: Exchanging is disabled");
        require(sourceCurrencyKey == "KUSD" || destinationCurrencyKey == "KUSD",
            "Foundry: exchange the symbol must have KUSD");

        // Note: We don't need to check their balance as the burn() below will do a safe subtraction which requires
        // the subtraction to not overflow, which would happen if their balance is not sufficient.

        // Burn the source amount
        combos[sourceCurrencyKey].burn(from, sourceAmount);

        // How much should they get in the destination currency?
        uint destinationAmount = effectiveValue(sourceCurrencyKey, sourceAmount, destinationCurrencyKey);

        // What's the fee on that currency that we should deduct?
        uint amountReceived = destinationAmount;
        uint fee = 0;

        if (chargeFee) {
            // Get the exchange fee rate
            uint exchangeFeeRate = feeRateForExchange(sourceCurrencyKey, destinationCurrencyKey);
            amountReceived = destinationAmount.wmul(UNIT.sub(exchangeFeeRate));

            fee = destinationAmount.sub(amountReceived);
        }

        // Issue their new combos
        combos[destinationCurrencyKey].issue(destinationAddress, amountReceived);

        // Remit the fee in KUSD
        if (fee > 0) {
            uint usdkFeeAmount = fee;
            if (destinationCurrencyKey != "KUSD") {
                usdkFeeAmount = effectiveValue(destinationCurrencyKey, fee, "KUSD");
            }
            combos["KUSD"].issue(feePool().FEE_ADDRESS(), usdkFeeAmount);
            feePool().recordFeePaid(usdkFeeAmount);
        }

        // Nothing changes as far as issuance data goes because the total value in the system hasn't changed.        

        //Let the DApps know there was a Combo exchange
        emitComboExchange(from, sourceCurrencyKey, sourceAmount, destinationCurrencyKey,
            amountReceived, destinationAddress, fee);

        return true;
    }

    /**
     * @notice Function that registers new combo as they are issued. Calculate delta to append to FoundryStorage.
     * @dev Only internal calls from Foundry address.
     * @param currencyKey The currency to register combos in, for example sUSD or sAUD
     * @param amount The amount of combos to register with a base of UNIT
     */
    function _addToDebtRegister(bytes32 currencyKey, uint amount)
        internal
    {
        // What is the value of the requested debt in KUSDs?
        uint usdkValue = effectiveValue(currencyKey, amount, "KUSD");

        // What is the value of all issued combos of the system (priced in KUSD)?
        uint totalDebtIssued = totalIssuedCombos("KUSD");

        // What will the new total be including the new value?
        uint newTotalDebtIssued = usdkValue.add(totalDebtIssued);

        // What is their percentage (as a high precision int) of the total debt?
        uint debtPercentage = usdkValue.wdivRound(newTotalDebtIssued);

        // And what effect does this percentage change have on the global debt holding of other issuers?
        // The delta specifically needs to not take into account any existing debt as it's already
        // accounted for in the delta from when they issued previously.
        // The delta is a high precision integer.
        uint delta = UNIT.sub(debtPercentage);

        // How much existing debt do they have?
        uint existingDebt = debtBalanceOf(caller, "KUSD");

        // And what does their debt ownership look like including this previous stake?
        if (existingDebt > 0) {
            debtPercentage = usdkValue.add(existingDebt).wdivRound(newTotalDebtIssued);
        }

        // Are they a new issuer? If so, record them.
        if (existingDebt == 0) {
            foundryStorage.incrementTotalIssuerCount();
        }

        // Save the debt entry parameters
        foundryStorage.setCurrentIssuanceData(caller, debtPercentage);

        // And if we're the first, push 1 as there was no effect to any other holders, otherwise push
        // the change for the rest of the debt holders. The debt ledger holds high precision integers.
        if (foundryStorage.debtLedgerLength() > 0) {
            foundryStorage.appendDebtLedgerValue(
                foundryStorage.lastDebtLedgerEntry().wmulRound(delta)
            );
        } else {
            foundryStorage.appendDebtLedgerValue(UNIT);
        }
    }

    /**
     * @notice Issue combos against the sender's KPT.
     * @dev Issuance is only allowed if the foundry price isn't stale. Amount should be larger than 0.
     * @param amount The amount of combos you wish to issue with a base of UNIT
     */
    function issueCombos(uint amount)
        public
        optionalProxy
        // No need to check if price is stale, as it is checked in issuableCombos.
    {
        bytes32 currencyKey = "KUSD";

        require(amount <= remainingIssuableCombos(caller, currencyKey), "Foundry: Amount too large");

        // Keep track of the debt they're about to create
        _addToDebtRegister(currencyKey, amount);

        // Create their combos
        combos[currencyKey].issue(caller, amount);

        // Store their locked KPT amount to determine their fee % for the period
        _appendAccountIssuanceRecord();

        emitComboIssueOrBurn(caller, currencyKey, amount, "issue");
    }

    /**
     * @notice Issue the maximum amount of Synths possible against the sender's KPT.
     * @dev Issuance is only allowed if the Foundry price isn't stale.
     */
    function issueMaxCombos()
        external
        optionalProxy
    {
        bytes32 currencyKey = "KUSD";

        // Figure out the maximum we can issue in that currency
        uint maxIssuable = remainingIssuableCombos(caller, currencyKey);

        // Keep track of the debt they're about to create
        _addToDebtRegister(currencyKey, maxIssuable);

        // Create their combos
        combos[currencyKey].issue(caller, maxIssuable);

        // Store their locked KPT amount to determine their fee % for the period
        _appendAccountIssuanceRecord();

        emitComboIssueOrBurn(caller, currencyKey, maxIssuable, "issue");
    }

    /**
     * @notice Burn combos to clear issued combos/free KPT.
     * @param amount The amount (in UNIT base) you wish to burn
     * @dev The amount to burn is debased to KUSD's
     */
    function burnCombos(uint amount)
        external
        optionalProxy
        // No need to check for stale rates as effectiveValue checks rates
    {
        _internalBurnCombos(caller, amount);
    }

    function burnAllCombos()
        external
        optionalProxy
    {
        _internalBurnCombos(caller, combos["KUSD"].balanceOf(caller));
    }

    function _internalBurnCombos(address caller, uint amount) internal {
        bytes32 currencyKey = "KUSD";

        // How much debt do they have?
        uint debtToRemove = effectiveValue(currencyKey, amount, "KUSD");
        uint existingDebt = debtBalanceOf(caller, "KUSD");

        require(existingDebt > 0, "Foundry: No debt to forgive");

        // If they're trying to burn more debt than they actually owe, rather than fail the transaction, let's just
        // clear their debt and leave them be.
        uint amountToRemove = existingDebt < debtToRemove ? existingDebt : debtToRemove;

        // Remove their debt from the ledger
        _removeFromDebtRegister(amountToRemove, existingDebt);

        uint amountToBurn = existingDebt < amount ? existingDebt : amount;

        // combo.burn does a safe subtraction on balance (so it will revert if there are not enough combos).
        combos[currencyKey].burn(caller, amountToBurn);

        // Store their debtRatio against a feeperiod to determine their fee/rewards % for the period
        _appendAccountIssuanceRecord();

        emitComboIssueOrBurn(caller, currencyKey, amountToBurn, "burn");
    }

    function move(address account, address from, uint amount) external onlyPrivatePlacement {
        bytes32 currencyKey = "KUSD";
        ICombo combo = combos[currencyKey];
        combo.foundryToTransferFrom(from, account, amount);
        uint existingDebt = debtBalanceOf(account, "KUSD");
        uint balance = combo.balanceOf(account);
        require(balance >= existingDebt, "Foundry: balance less than existing debt");
        _removeFromDebtRegister(existingDebt, existingDebt);
        combos[currencyKey].burn(account, existingDebt);
        _appendAccountIssuanceRecord();
        emitComboLiquidation(account, currencyKey, existingDebt);
    }

    function flux(address seller, address buyer, uint256 amount) external onlyPrivatePlacement {
        foundryExtend().flux(seller, buyer, amount);
    }

    /**
     * @notice Store in the FeePool the users current debt value in the system in KUSDs.
     * @dev debtBalanceOf(caller, "KUSD") to be used with totalIssuedCombos("KUSD") to get
     *  users % of the system within a feePeriod.
     */
    function _appendAccountIssuanceRecord()
        internal
    {
        uint initialDebtOwnership;
        uint debtEntryIndex;
        (initialDebtOwnership, debtEntryIndex) = foundryStorage.issuanceData(caller);
        feePool().appendAccountIssuanceRecord(
            caller,
            initialDebtOwnership,
            debtEntryIndex
        );
    }

    /**
     * @notice Remove a debt position from the register
     * @param amount The amount (in UNIT base) being presented in KUSDs
     * @param existingDebt The existing debt (in UNIT base) of address presented in KUSDs
     */
    function _removeFromDebtRegister(uint amount, uint existingDebt)
        internal
    {
        uint debtToRemove = amount;

        // What is the value of all issued combos of the system (priced in KUSDs)?
        uint totalDebtIssued = totalIssuedCombos("KUSD");

        // What will the new total after taking out the withdrawn amount
        uint newTotalDebtIssued = totalDebtIssued.sub(debtToRemove);

        uint delta = 0;

        // What will the debt delta be if there is any debt left?
        // Set delta to 0 if no more debt left in system after user
        if (newTotalDebtIssued > 0) {

            // What is the percentage of the withdrawn debt (as a high precision int) of the total debt after?
            uint debtPercentage = debtToRemove.wdivRound(newTotalDebtIssued);

            // And what effect does this percentage change have on the global debt holding of other issuers?
            // The delta specifically needs to not take into account any existing debt as it's already
            // accounted for in the delta from when they issued previously.
            delta = UNIT.add(debtPercentage);
        }

        // Are they exiting the system, or are they just decreasing their debt position?
        if (debtToRemove == existingDebt) {
            foundryStorage.setCurrentIssuanceData(caller, 0);
            foundryStorage.decrementTotalIssuerCount();
        } else {
            // What percentage of the debt will they be left with?
            uint newDebt = existingDebt.sub(debtToRemove);
            uint newDebtPercentage = newDebt.wdivRound(newTotalDebtIssued);

            // Store the debt percentage and debt ledger as high precision integers
            foundryStorage.setCurrentIssuanceData(caller, newDebtPercentage);
        }

        // Update our cumulative ledger. This is also a high precision integer.
        foundryStorage.appendDebtLedgerValue(
            foundryStorage.lastDebtLedgerEntry().wmulRound(delta)
        );
    }

    // ========== Issuance/Burning ==========

    /**
     * @notice The maximum combos an issuer can issue against their total foundry quantity, priced in KUSDs.
     * This ignores any already issued combos, and is purely giving you the maximimum amount the user can issue.
     */
    function maxIssuableCombos(address issuer, bytes32 currencyKey)
        public
        view
        // We don't need to check stale rates here as effectiveValue will do it for us.
        returns (uint)
    {
        // What is the value of their KPT balance in the destination currency?
        uint destinationValue = effectiveValue("KPT", collateral(issuer), currencyKey);

        // They're allowed to issue up to issuanceRatio of that value
        return destinationValue.wmul(foundryStorage.issuanceRatio());
    }

    /**
     * @notice The current collateralisation ratio for a user. Collateralisation ratio varies over time
     * as the value of the underlying Foundry asset changes,
     * e.g. based on an issuance ratio of 20%. if a user issues their maximum available
     * combos when they hold $10 worth of Foundry, they will have issued $2 worth of combos. If the value
     * of Foundry changes, the ratio returned by this function will adjust accordingly. Users are
     * incentivised to maintain a collateralisation ratio as close to the issuance ratio as possible by
     * altering the amount of fees they're able to claim from the system.
     */
    function collateralisationRatio(address issuer)
        public
        view
        returns (uint)
    {
        uint totalOwnedFoundry = collateral(issuer);
        if (totalOwnedFoundry == 0) return 0;

        uint debtBalance = debtBalanceOf(issuer, "KPT");
        return debtBalance.wdivRound(totalOwnedFoundry);
    }

    /**
     * @notice If a user issues combos backed by KPT in their wallet, the KPT become locked. This function
     * will tell you how many combos a user has to give back to the system in order to unlock their original
     * debt position. This is priced in whichever combo is passed in as a currency key, e.g. you can price
     * the debt in KUSD, or any other combo you wish.
     */
    function debtBalanceOf(address issuer, bytes32 currencyKey)
        public
        view
        // Don't need to check for stale rates here because totalIssuedCombos will do it for us
        returns (uint)
    {
        // What was their initial debt ownership?
        uint initialDebtOwnership;
        uint debtEntryIndex;
        (initialDebtOwnership, debtEntryIndex) = foundryStorage.issuanceData(issuer);

        // If it's zero, they haven't issued, and they have no debt.
        if (initialDebtOwnership == 0) return 0;

        // Figure out the global debt percentage delta from when they entered the system.
        // This is a high precision integer of 27 (1e27) decimals.
        uint currentDebtOwnership = foundryStorage.lastDebtLedgerEntry()
            .wdivRound(foundryStorage.debtLedger(debtEntryIndex))
            .wmulRound(initialDebtOwnership);

        // What's the total value of the system in their requested currency?
        uint totalSystemValue = totalIssuedCombos(currencyKey);

        // Their debt balance is their portion of the total system value.
        //uint highPrecisionBalance = totalSystemValue.decimalToPreciseDecimal()
          //  .multiplyDecimalRoundPrecise(currentDebtOwnership);

        // Convert back into 18 decimals (1e18)
        //return highPrecisionBalance.preciseDecimalToDecimal();
        return totalSystemValue.wmulRound(currentDebtOwnership);
    }

    /**
     * @notice The remaining combos an issuer can issue against their total foundry balance.
     * @param issuer The account that intends to issue
     * @param currencyKey The currency to price issuable value in
     */
    function remainingIssuableCombos(address issuer, bytes32 currencyKey)
        public
        view
        // Don't need to check for combo existing or stale rates because maxIssuableCombos will do it for us.
        returns (uint)
    {
        uint alreadyIssued = debtBalanceOf(issuer, currencyKey);
        uint max = maxIssuableCombos(issuer, currencyKey);

        if (alreadyIssued >= max) {
            return 0;
        } else {
            return max.sub(alreadyIssued);
        }
    }

    /**
     * @notice The total KPT owned by this account, both escrowed and unescrowed,
     * against which combos can be issued.
     * This includes those already being used as collateral (locked), and those
     * available for further issuance (unlocked).
     */
    function collateral(address account)
        public
        view
        returns (uint)
    {
        uint balance = foundryExtend().kptBalanceOf(account);

        if (address(reward()) != address(0)) {
            balance = balance.add(reward().deposited(account));
        }

        return balance;
    }

    function getComboLength() public view returns (uint) {
        return availableCombos.length;
    }

    function distribute(uint256 amount) public onlyMortgage {
        distribution().distribute(amount);
    }

    function balanceOf(address account) public view returns (uint) {
        return mortgage().balanceOf(account);
    }

    function allMortgated() public view returns (address[] memory) {
        return foundryStorage.getAllMortgated();
    }

    // ========== MODIFIERS ==========

    modifier rateNotStale(bytes32 currencyKey) {
        require(!rates().isExpired(currencyKey), "Foundry: Rate stale or not a combo");
        _;
    }

    modifier onlyFoundryExtend() {
        require(msg.sender == address(foundryExtend()), "Foundry: Only foundryExtend allowed");
        _;
    }

    modifier onlyMortgage() {
        require(msg.sender == address(mortgage()), "Foundry: Only mortgage allowed");
        _;
    }

    modifier onlyPrivatePlacement() {
        require(msg.sender == address(privatePlacement()), "Foundry: Only privatePlacement allowed");
        _;
    }

    modifier onlyOracle
    {
        //require(msg.sender == exchangeRates.oracle(), "Foundry: Only oracle allowed");
        _;
    }

    // ========== EVENTS ==========
    /* solium-disable */
    event ComboExchange(address indexed account, bytes32 fromCurrencyKey, uint256 fromAmount, bytes32 toCurrencyKey,
        uint256 toAmount, address toAddress, uint256 fee);
    bytes32 constant COMBOEXCHANGE_SIG = keccak256("ComboExchange(address,bytes32,uint256,bytes32,uint256,address,uint256)");
    function emitComboExchange(address account, bytes32 fromCurrencyKey, uint256 fromAmount, bytes32 toCurrencyKey,
        uint256 toAmount, address toAddress, uint256 feeAmount) internal {
        proxy().note(abi.encode(fromCurrencyKey, fromAmount, toCurrencyKey, toAmount, toAddress, feeAmount), 2, COMBOEXCHANGE_SIG,
            account.encode(), 0, 0);
    }

    /* solium-enable */

    bytes32 constant COMBOCHANGE_SIG = keccak256("ComboIssueOrBurn(address,bytes32,uint256,bytes32)");

    function emitComboIssueOrBurn(address account, bytes32 currencyKey, uint256 amount, bytes32 operation) internal {
        proxy().note(abi.encode(account, currencyKey, amount, operation), 2, COMBOCHANGE_SIG, account.encode(), 0, 0);
    }

    bytes32 constant LIQUIDATION_SIG = keccak256("ComboLiquidation(address,bytes32,uint256)");
    function emitComboLiquidation(address account, bytes32 currencyKey, uint256 burnAmount) internal {
        proxy().note(abi.encode(account, currencyKey, burnAmount), 2, LIQUIDATION_SIG, account.encode(), 0, 0);
    }

    function() external {

    }
}
