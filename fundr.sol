pragma solidity ^0.5.2;

interface FundrUpgrade {
    // This interface is intended for upgrading to a new contract.
    // See upgradeCreator for details.
    function from_upgrade(address user_address, uint[] calldata data) external payable;
}

contract Fundr {

    // From https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary
    uint constant SECONDS_PER_DAY = 24 * 60 * 60;
    int constant OFFSET19700101 = 2440588;

    // ------------------------------------------------------------------------
    // Calculate year/month/day from the number of days since 1970/01/01 using
    // the date conversion algorithm from
    //   http://aa.usno.navy.mil/faq/docs/JD_Formula.php
    // and adding the offset 2440588 so that 1970/01/01 is day 0
    //
    // int L = days + 68569 + offset
    // int N = 4 * L / 146097
    // L = L - (146097 * N + 3) / 4
    // year = 4000 * (L + 1) / 1461001
    // L = L - 1461 * year / 4 + 31
    // month = 80 * L / 2447
    // dd = L - 2447 * month / 80
    // L = month / 11
    // month = month + 2 - 12 * L
    // year = 100 * (N - 49) + year + L
    // ------------------------------------------------------------------------
    function _daysToDate(uint _days) private pure returns (uint year, uint month, uint day) {
        int __days = int(_days);

        int L = __days + 68569 + OFFSET19700101;
        int N = 4 * L / 146097;
        L = L - (146097 * N + 3) / 4;
        int _year = 4000 * (L + 1) / 1461001;
        L = L - 1461 * _year / 4 + 31;
        int _month = 80 * L / 2447;
        int _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint(_year);
        month = uint(_month);
        day = uint(_day);
    }

    // Gets the number of months since Epoch.
    function getTotalMonth(uint timestamp) private pure returns (uint month) {
        uint year;
        uint day;
        (year, month, day) = _daysToDate(timestamp / SECONDS_PER_DAY);
        month += year * 12;
    }


    //-----------------------------------
    // CONTRACT STARTS
    //-----------------------------------

    enum ChangeType {
        CREATE, UPDATE, DELETE
    }

    event CreatorChanged (
        ChangeType change,
        address creator
    );

    event FundingTypeChanged (
        ChangeType change,
        address creator,
        uint id
    );

    event PledgeChanged (
        ChangeType change,
        address creator,
        uint fundingTypeId,
        uint id
    );

    event ChargeEvent (
        uint chargeId,
        address creator,
        uint fundingTypeId,
        uint maxAmount,
        bool partialCharge,
        string comment,
        address[] chargedPledgers,
        uint[] chargedAmounts,
        address chargedBy
    );

    event DepositEvent (
        address from,
        uint amount
    );

    event WithdrawEvent (
        address to,
        uint amount
    );

    event OnetimePaymentEvent (
        address from,
        address to,
        uint amount
    );

    event UpgradeEvent (
        address creatorAddress,
        uint amount,
        address newContractAddress,
        uint[] data
    );

    event TransferEvent (
        address creatorAddress,
        address newCreatorAddress,
        uint amount
    );




    struct Pledge {
        bool active;
        uint index;
        address pledger;
        uint amount;
        uint maxPerMonth;
        string comment;

        uint amountLeftThisMonth;
        uint currentMonth;
    }

    struct FundingType {
        bool active;
        uint index;
        string name;
        string description;
        uint minimumAmount;
        uint[] pledgeIds;
        mapping(uint => Pledge) pledges;
        uint nextPledgeId;
    }

    struct Creator {
        bool active;
        uint index;
        string name;
        string description;
        string links;
        uint[] fundingTypeIds;
        mapping(uint => FundingType) fundingTypes;
        uint nextFundingTypeId;
        address chargeDelegate;
    }

    address public owner;
    mapping (address => uint) public balances;
    mapping (address => Creator) public creators;
    address[] public creatorAddresses;

    constructor() public {
        owner = msg.sender;
    }

    function getCreatorAddresses() public view returns (address[] memory) {
        return creatorAddresses;
    }

    function getFundingTypeIds(address creatorAddress) public view returns (uint[] memory) {
        return creators[creatorAddress].fundingTypeIds;
    }

    function getFundingType(address creatorAddress, uint fundingTypeId) public view returns (string memory, string memory, uint) {
        FundingType storage ft = creators[creatorAddress].fundingTypes[fundingTypeId];
        return (ft.name, ft.description, ft.minimumAmount);
    }

    function getPledgeIds(address creatorAddress, uint fundingTypeId) public view returns (uint[] memory) {
        return creators[creatorAddress].fundingTypes[fundingTypeId].pledgeIds;
    }

    function getPledge(address creatorAddress, uint fundingTypeId, uint pledgeId) public view returns (uint, address, uint, uint, string memory, uint, uint) {
        Pledge storage p = creators[creatorAddress].fundingTypes[fundingTypeId].pledges[pledgeId];
        return (p.index, p.pledger, p.amount, p.maxPerMonth, p.comment, p.amountLeftThisMonth, p.currentMonth);
    }

    function deposit(uint amount) public payable {
        // Deposit ETH to the contract.
        //
        // Args:
        //  amount: The amount of ETH to deposit.
        //  value: Same as amount.
        //
        // Emits:
        //  DepositEvent

        require(msg.value == amount, "Pass value as parameter.");
        balances[msg.sender] += msg.value;
        emit DepositEvent(msg.sender, amount);
    }

    function withdraw(uint amount) public {
        // Withdraw ETH from the contract.
        //
        // Args:
        //  amount: The amount of ETH to withdraw.
        //
        // Emits:
        //  WithdrawEvent

        require(balances[msg.sender] >= amount, "Not enough funds.");
        balances[msg.sender] -= amount;
        msg.sender.transfer(amount);
        emit WithdrawEvent(msg.sender, amount);
    }

    function onetimePayment(uint amount, address recepient) public {
        // Transfer an amount to another balance.
        //
        // Args:
        //  amount: The amount of ETH to transfer.
        //  recepient: Address of the recepient.
        //
        // Emits:
        //  OnetimePaymentEvent

        require(balances[msg.sender] >= amount, "Not enough funds.");
        balances[msg.sender] -= amount;
        balances[recepient] += amount;
        emit OnetimePaymentEvent(msg.sender, recepient, amount);
    }


    function updateCreator(string memory name, string memory description, string memory links, address chargeDelegate) public {
        // Updates the user's creator profile and creates it if it does not exist.
        //
        // Args:
        //  name: The creator's name.
        //  description: A description.
        //  links: A comma-separated list of links, e.g. the creator's YouTube profile.
        //  chargeDelegate: An address that can be used to charge funding types of this account.
        //
        // Emits:
        //  CreatorChanged

        require(bytes(name).length > 0, "Name can not be empty");
        Creator storage creator = creators[msg.sender];
        if(!creator.active){
            uint new_length = creatorAddresses.push(msg.sender);
            creator.index = new_length - 1;
            creator.active = true;
            emit CreatorChanged(ChangeType.CREATE, msg.sender);
        } else {
            emit CreatorChanged(ChangeType.UPDATE, msg.sender);
        }
        creator.name = name;
        creator.description = description;
        creator.links = links;
        creator.chargeDelegate = chargeDelegate;
    }

    function deleteCreator() public {
        // Deletes the user's creator profile.
        //
        // Emits:
        //  CreatorChanged

        Creator storage creator = creators[msg.sender];
        require(creator.active, "Creator inactive.");
        require(creator.fundingTypeIds.length == 0, "Must remove all funding types.");
        uint index = creator.index;
        require(creatorAddresses[index] == msg.sender, "Bad index.");
        if(index < creatorAddresses.length - 1){
            creatorAddresses[index] = creatorAddresses[creatorAddresses.length - 1];
            creators[creatorAddresses[index]].index = index;
        }
        creatorAddresses.length--;
        delete creators[msg.sender];
        emit CreatorChanged(ChangeType.DELETE, msg.sender);
    }

    function addFundingType(string memory name, string memory description, uint minimumAmount) public {
        // Adds a funding type.
        //
        // Args:
        //  name: The funding type's name.
        //  description: A description.
        //  minimumAmount: The minimum amount that pledgers can pledge to this funding type.
        //
        // Emits:
        //  FundingTypeChanged

        require(bytes(name).length > 0, "Name can not be empty");
        Creator storage creator = creators[msg.sender];
        require(creator.active, "Creator inactive.");
        uint id = creator.nextFundingTypeId++;
        FundingType storage fundingType = creator.fundingTypes[id];
        fundingType.active = true;
        fundingType.name = name;
        fundingType.description = description;
        fundingType.minimumAmount = minimumAmount;
        uint new_length = creators[msg.sender].fundingTypeIds.push(id);
        fundingType.index = new_length - 1;
        emit FundingTypeChanged(ChangeType.CREATE, msg.sender, id);
    }

    function editFundingType(uint fundingTypeId, string memory name, string memory description, uint minimumAmount) public {
        // Edits a funding type.
        //
        // Args:
        //  fundingTypeId: The id of the funding type.
        //  ...see addFundingType
        //
        // Emits:
        //  FundingTypeChanged

        require(bytes(name).length > 0, "Name can not be empty");
        Creator storage creator = creators[msg.sender];
        require(creator.active, "Creator inactive.");
        FundingType storage fundingType = creator.fundingTypes[fundingTypeId];
        require(fundingType.active, "Funding type must be active");
        fundingType.name = name;
        fundingType.description = description;
        fundingType.minimumAmount = minimumAmount;
        emit FundingTypeChanged(ChangeType.UPDATE, msg.sender, fundingTypeId);
    }

    function removeFundingType(uint fundingTypeId) public {
        // Removes a funding type.
        //
        // Args:
        //  fundingTypeId: The id of the funding type.
        //
        // Emits:
        //  FundingTypeChanged

        Creator storage creator = creators[msg.sender];
        FundingType storage fundingType = creator.fundingTypes[fundingTypeId];
        require(fundingType.active, "Funding type inactive.");
        
        for (uint i=0; i<fundingType.pledgeIds.length; i++){
            delete fundingType.pledges[fundingType.pledgeIds[i]];
        }
        fundingType.pledgeIds.length = 0;

        uint[] storage fundingTypeIds = creator.fundingTypeIds;
        uint index = fundingType.index;
        if (index < creator.fundingTypeIds.length - 1){
            fundingTypeIds[index] = fundingTypeIds[fundingTypeIds.length - 1];
            creator.fundingTypes[fundingTypeIds[index]].index = index;
        }
        fundingTypeIds.length--;
        delete creator.fundingTypes[fundingTypeId];
        emit FundingTypeChanged(ChangeType.DELETE, msg.sender, fundingTypeId);
    }

    function createPledge(address creatorAddress, uint fundingTypeId, uint amount, uint maxPerMonth, string memory comment) public {
        // Creates a pledge to a creator's funding type.
        //
        // Args:
        //  creatorAddress: The address of the creator.
        //  amount: The amount to give per charge.
        //  maxPerMonth: Maximum amount that can be charged from this pledge per month.
        //  fundingTypeId: The id of the funding type to pledge to.
        //  comment: A comment.
        //
        // Emits:
        //  PledgeChanged

        require(amount <= maxPerMonth, "Amount must be smaller than maxPerMonth.");
        require(balances[msg.sender] > 0, "Balance required.");
        FundingType storage fundingType = _getFundingType(creatorAddress, fundingTypeId);
        require(fundingType.active, "Funding type inactive.");
        require(amount >= fundingType.minimumAmount, "Amount must be larger than minimum.");
        uint id = fundingType.nextPledgeId++;
        Pledge storage pledge = fundingType.pledges[id];
        pledge.active = true;
        pledge.pledger = msg.sender;
        pledge.amount = amount;
        pledge.maxPerMonth = maxPerMonth;
        pledge.comment = comment;
        uint new_length = fundingType.pledgeIds.push(id);
        pledge.index = new_length - 1;
        emit PledgeChanged(ChangeType.CREATE, creatorAddress, fundingTypeId, id);
    }

    function _removePledge(address creatorAddress, FundingType storage fundingType, uint fundingTypeId, uint pledgeId) private {
        Pledge storage pledge = fundingType.pledges[pledgeId];
        if(!pledge.active){
            return;
        }
        require(msg.sender == creatorAddress || msg.sender == pledge.pledger, "Not authorized to delete pledge.");
        if(pledge.index < fundingType.pledgeIds.length - 1){
            fundingType.pledgeIds[pledge.index] = fundingType.pledgeIds[fundingType.pledgeIds.length - 1];
            fundingType.pledges[fundingType.pledgeIds[pledge.index]].index = pledge.index;
        }
        fundingType.pledgeIds.length--;
        delete fundingType.pledges[pledgeId];
        emit PledgeChanged(ChangeType.DELETE, creatorAddress, fundingTypeId, pledgeId);
    }

    function removePledgesById(address creatorAddress, uint fundingTypeId, uint[] memory pledgeIds) public {
        // Removes multiple pledges.
        //
        // Args:
        //  creatorAddress: Address of the creator.
        //  fundingTypeId: The id of the funding type.
        //  pledgeIds: The ids of the pledges.
        //
        // Emits:
        //  PledgeChanged (multiple)

        FundingType storage fundingType = _getFundingType(creatorAddress, fundingTypeId);
        for(uint i=0; i<pledgeIds.length; i++){
            _removePledge(creatorAddress, fundingType, fundingTypeId, pledgeIds[i]);
        }
    }

    function removePledge(address creatorAddress, uint fundingTypeId, uint pledgeId) public {
        // Removes a pledge.
        //
        // Args:
        //  creatorAddress: Address of the creator.
        //  fundingTypeId: The id of the funding type.
        //  pledgeId: The id of the pledge.
        //
        // Emits:
        //  PledgeChanged

        FundingType storage fundingType = _getFundingType(creatorAddress, fundingTypeId);
        _removePledge(creatorAddress, fundingType, fundingTypeId, pledgeId);
    }

    function _getFundingType(address creatorAddress, uint fundingTypeId) private view returns (FundingType storage fundingType) {
        Creator storage creator = creators[creatorAddress];
        require(creator.active, "Creator inactive.");
        fundingType = creator.fundingTypes[fundingTypeId];
        require(fundingType.active, "Funding type inactive.");
    }

    function _getFundingTypeForCharge(address creatorAddress, uint fundingTypeId) private view returns (FundingType storage fundingType) {
        Creator storage creator = creators[creatorAddress];
        require(creator.active, "Creator inactive.");
        require(creatorAddress == msg.sender || creator.chargeDelegate == msg.sender, "Call must come from creator or their charge delegate.");
        fundingType = creator.fundingTypes[fundingTypeId];
        require(fundingType.active, "Funding type inactive.");
    }

    function _min(uint a, uint b) private pure returns (uint c) {
        c = a <= b ? a : b;
    }

    function _chargePledge(uint currentMonth, uint maxAmount, bool partialCharge, Pledge storage pledge) private returns (uint){
        if(!pledge.active){
            return 0;
        }
        uint amount = pledge.amount;
        if(currentMonth != pledge.currentMonth){
            pledge.currentMonth = currentMonth;
            pledge.amountLeftThisMonth = pledge.maxPerMonth;
        }
        uint _maxAmount = _min(balances[pledge.pledger], pledge.amountLeftThisMonth);
        if (maxAmount > 0 && maxAmount < _maxAmount){
            _maxAmount = maxAmount;
        }
        if(amount > _maxAmount){
            if(_maxAmount > 0 && partialCharge){
                amount = _maxAmount;
            }else{
                return 0;
            }
        }
        balances[pledge.pledger] -= amount;
        pledge.amountLeftThisMonth -= amount;
        balances[msg.sender] += amount;
        return amount;
    }

    function charge(address creatorAddress, uint chargeId, uint fundingTypeId, uint maxAmount, bool partialCharge, string memory comment) public {
        // Charges all pledges in a funding type.
        //
        // Args:
        //  creatorAddress: Address of the creator.
        //  chargeId: Arbitrary value to be logged.
        //  fundingTypeId: The id of the funding type.
        //  maxAmount: The maximum amount to charge. 0 for no maximum.
        //  partialCharge: If true, pledgers that don't have the full charge amount 
        //                 in their balance are still charged whatever they have left.
        //  comment: A comment.
        //
        // Emits:
        //  ChargeEvent

        FundingType storage fundingType = _getFundingTypeForCharge(creatorAddress, fundingTypeId);
        uint currentMonth = getTotalMonth(now);
        uint[] storage pledgeIds = fundingType.pledgeIds;
        address[] memory chargedPledgers = new address[](pledgeIds.length);
        uint[] memory chargedAmounts = new uint[](pledgeIds.length);
        for(uint i=0; i<pledgeIds.length; i++){
            uint pledgeId = pledgeIds[i];
            Pledge storage pledge = fundingType.pledges[pledgeId];
            uint chargedAmount = _chargePledge(currentMonth, maxAmount, partialCharge, pledge);
            chargedPledgers[i] = pledge.pledger;
            chargedAmounts[i] = chargedAmount;
        }
        emit ChargeEvent(chargeId, msg.sender, fundingTypeId, maxAmount, partialCharge, comment, chargedPledgers, chargedAmounts, msg.sender);
    }

    function chargeSelectivelyById(address creatorAddress, uint chargeId, uint fundingTypeId, uint maxAmount, bool partialCharge, string memory comment, uint[] memory pledgeIds) public {
        // Charges pledges in a funding type by Id.
        //
        // Args:
        //  creatorAddress: Address of the creator.
        //  chargeId: Arbitrary value to be logged.
        //  fundingTypeId: The id of the funding type.
        //  maxAmount: The maximum amount to charge. 0 for no maximum.
        //  partialCharge: If true, pledgers that don't have the full charge amount 
        //                 in their balance are still charged whatever they have left.
        //  comment: A comment.
        //  pledgeIds: Ids of the pledges to charge.
        //
        // Emits:
        //  ChargeEvent

        FundingType storage fundingType = _getFundingTypeForCharge(creatorAddress, fundingTypeId);
        uint currentMonth = getTotalMonth(now);
        address[] memory chargedPledgers = new address[](pledgeIds.length);
        uint[] memory chargedAmounts = new uint[](pledgeIds.length);
        for(uint i=0; i<pledgeIds.length; i++){
            uint pledgeId = pledgeIds[i];
            Pledge storage pledge = fundingType.pledges[pledgeId];
            uint chargedAmount = _chargePledge(currentMonth, maxAmount, partialCharge, pledge);
            chargedPledgers[i] = pledge.pledger;
            chargedAmounts[i] = chargedAmount;
        }
        emit ChargeEvent(chargeId, msg.sender, fundingTypeId, maxAmount, partialCharge, comment, chargedPledgers, chargedAmounts, msg.sender);
    }

    function chargeSelectivelyByIndexRange(address creatorAddress, uint chargeId, uint fundingTypeId, uint maxAmount, bool partialCharge, string memory comment, uint startIndex, uint endIndex) public {
        // Charges pledges in a funding type by index. Be careful with this.
        //
        // Args:
        //  creatorAddress: Address of the creator.
        //  chargeId: Arbitrary value to be logged.
        //  fundingTypeId: The id of the funding type.
        //  maxAmount: The maximum amount to charge. 0 for no maximum.
        //  partialCharge: If true, pledgers that don't have the full charge amount 
        //                 in their balance are still charged whatever they have left.
        //  comment: A comment.
        //  startIndex: The start index in the pledgeIds list.
        //  endIndex: The end index in the pledgeIds list.
        //
        // Emits:
        //  ChargeEvent

        FundingType storage fundingType = _getFundingTypeForCharge(creatorAddress, fundingTypeId);
        uint currentMonth = getTotalMonth(now);
        if (endIndex > fundingType.pledgeIds.length){
            endIndex = fundingType.pledgeIds.length;
        }
        uint numPledges = endIndex - startIndex;
        address[] memory chargedPledgers = new address[](numPledges);
        uint[] memory chargedAmounts = new uint[](numPledges);
        for(uint index = startIndex; index < endIndex ; index++){
            Pledge storage pledge = fundingType.pledges[fundingType.pledgeIds[index]];
            uint chargedAmount = _chargePledge(currentMonth, maxAmount, partialCharge, pledge);
            chargedPledgers[index] = pledge.pledger;
            chargedAmounts[index] = chargedAmount;
        }
        emit ChargeEvent(chargeId, msg.sender, fundingTypeId, maxAmount, partialCharge, comment, chargedPledgers, chargedAmounts, msg.sender);
    }

    function upgradeCreator(address payable newContractAddress, uint[] memory data) public {
        // Sends all money to a new contract.
        //
        // Args:
        //  newContractAddress: The address of the new contract.
        //  data: Arbitrary data.
        //
        // Emits:
        //  UpgradeEvent

        FundrUpgrade up = FundrUpgrade(newContractAddress);
        uint amount = balances[msg.sender];
        require(amount > 0, "Must have positive balance.");
        balances[msg.sender] -= amount;
        up.from_upgrade.value(amount)(msg.sender, data);
        emit UpgradeEvent(msg.sender, amount, newContractAddress, data);
    }

}
