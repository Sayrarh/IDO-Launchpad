// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Launchpad {
    ///////////////EVENTS//////////////////
    event ProjectCreated(
        uint256 indexed projectId,
        address indexed projectOwner,
        address indexed token,
        uint256 tokenPrice,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 maxCap,
        uint256 startTimeInMinutes,
        uint256 endTimeInMinutes
    );

    event InvestmentMade(
        uint256 indexed projectId,
        address indexed investor,
        uint256 amountInvested
    );

    event AllocationUpdated(address indexed participant, uint allocation);

    event TokenClaimed(address sender, uint256 amountToclaim);

    address public launchPadadmin;

    uint256 projectsCurrentId;

    //fee for launchpad

    struct Project {
        address projectOwner;
        IERC20 token;
        uint256 tokenPrice;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint256 maxCap; //IDO totalSupply
        uint256 startTimeInMinutes;
        uint256 endTimeInMinutes;
        bool isActive;
        uint256 totalAmountRaised;
        address[] allIDOPartcipants;
        bool withdrawn;
    }

    mapping(uint256 => mapping(address => uint256)) projectInvestments;
    mapping(address => bool) whitelistedTokens;
    mapping(address => bool) claimed;

    // The allocation of a particular IDO for each participant
    mapping(uint256 => mapping(address => uint256)) allocation;
    mapping(uint256 => Project) projects;

    ///////////////ERRORS//////////////////
    error NotLaunchPadAdmin();
    error TokenPriceMustBeGreaterThanZero();
    error MinimumInvestmentMustBeGreaterThanZero();
    error MaxInvestmentMustBeGreaterOrEqualToMinInvestment();
    error MaxCapMustBeGreaterOrEqualToMaxInvestment();
    error EndTimeMustBeGreaterThanStartTime();
    error InvalidProjectID();
    error ProjectNotActive();
    error ProjectCancelled();
    error AddressZero();
    error InvestmentAmtBelowMinimum();
    error InvestmentAmtExceedsMaximum();
    error ProjectNotStarted();
    error ProjectEnded();
    error NotProjectOwner();
    error AlreadyWithdrawn();
    error ProjectStillInProgress();
    error AlreadyClaimed();
    error NoInvestment();
    error TxnFailed();
    error TokenAlreadyWhitelisted();
    error ContractNotFullyFunded();

    constructor() {
        launchPadadmin = msg.sender;
    }

    function listProject(
        IERC20 _token,
        uint256 _tokenPrice,
        uint256 _minInvestment,
        uint256 _maxInvestment,
        uint256 _maxCap,
        uint256 _startTime,
        uint256 _endTime
    ) external {
        if (_tokenPrice == 0) revert TokenPriceMustBeGreaterThanZero();
        if (_minInvestment == 0)
            revert MinimumInvestmentMustBeGreaterThanZero();
        if (_maxInvestment < _minInvestment)
            revert MaxInvestmentMustBeGreaterOrEqualToMinInvestment();
        if (_maxInvestment > _maxCap)
            revert MaxCapMustBeGreaterOrEqualToMaxInvestment();

        if (
            ((_startTime * 1 minutes) + block.timestamp) >
            ((_endTime * 1 minutes) + block.timestamp)
        ) revert EndTimeMustBeGreaterThanStartTime();

        projectsCurrentId = projectsCurrentId + 1;

        Project storage project = projects[projectsCurrentId];

        if (whitelistedTokens[address(_token)] == true)
            revert TokenAlreadyWhitelisted();

        project.projectOwner = msg.sender;
        project.token = _token;
        project.tokenPrice = _tokenPrice;
        project.minInvestment = _minInvestment;
        project.maxInvestment = _maxInvestment;
        project.maxCap = _maxCap;
        project.startTimeInMinutes = (_startTime * 1 minutes) + block.timestamp;
        project.endTimeInMinutes = (_endTime * 1 minutes) + block.timestamp;
        //send token to the contract
        project.isActive = true;

        whitelistedTokens[address(_token)] = true;

        emit ProjectCreated(
            projectsCurrentId,
            msg.sender,
            address(_token),
            _tokenPrice,
            _minInvestment,
            _maxInvestment,
            _maxCap,
            _startTime,
            _endTime
        );
    }

    function invest(uint256 _projectId) external payable {
        if (_projectId > projectsCurrentId || _projectId == 0)
            revert InvalidProjectID();

        Project storage project = projects[_projectId];
        if (IERC20(project.token).balanceOf(address(this)) < project.maxCap)
            revert ContractNotFullyFunded();

        if (project.isActive == false) revert ProjectNotActive();
        if (block.timestamp < project.startTimeInMinutes)
            revert ProjectNotStarted();
        if (block.timestamp > project.endTimeInMinutes) revert ProjectEnded();

        if (msg.value < project.minInvestment)
            revert InvestmentAmtBelowMinimum();
        if (
            (projectInvestments[_projectId][msg.sender] + msg.value) >
            project.maxInvestment
        ) revert InvestmentAmtExceedsMaximum();

        projectInvestments[_projectId][msg.sender] =
            projectInvestments[_projectId][msg.sender] +
            msg.value;

        project.allIDOPartcipants.push(msg.sender);

        project.totalAmountRaised = project.totalAmountRaised + msg.value;

        updateAllocation(_projectId);

        emit InvestmentMade(
            _projectId,
            msg.sender,
            projectInvestments[_projectId][msg.sender]
        );
    }

    function updateAllocation(uint256 _projectId) private {
        Project storage project = projects[_projectId];
        uint256 totalRaised = project.totalAmountRaised;

        for (uint256 i; i < project.allIDOPartcipants.length; i++) {
            uint256 userContribution = projectInvestments[_projectId][
                project.allIDOPartcipants[i]
            ];
            allocation[_projectId][project.allIDOPartcipants[i]] =
                (userContribution / totalRaised) *
                project.maxCap;
        }

        emit AllocationUpdated(msg.sender, allocation[_projectId][msg.sender]);
    }

    function claimAllocation(uint256 _projectID) external {
        if (_projectID > projectsCurrentId || _projectID == 0)
            revert InvalidProjectID();
        if (projectInvestments[_projectID][msg.sender] == 0)
            revert NoInvestment();
        if (claimed[msg.sender] == true) revert AlreadyClaimed();
        Project storage project = projects[_projectID];
        if (block.timestamp < project.endTimeInMinutes)
            revert ProjectStillInProgress();

        uint256 amountToclaim = allocation[_projectID][msg.sender];

        claimed[msg.sender] = true;

        //// Transfer the allocated tokens to the participant.
        bool success = IERC20(project.token).transfer(
            msg.sender,
            amountToclaim
        );
        if (!success) revert TxnFailed();

        emit TokenClaimed(msg.sender, amountToclaim);
    }

    function withdrawAmountRaised(uint256 _projectID) external payable {
        if (_projectID > projectsCurrentId || _projectID == 0)
            revert InvalidProjectID();
        Project storage project = projects[_projectID];

        if (msg.sender != project.projectOwner) revert NotProjectOwner();
        if (project.withdrawn == true) revert AlreadyWithdrawn();

        if (block.timestamp < project.endTimeInMinutes)
            revert ProjectStillInProgress();
        uint256 amountRaised = project.totalAmountRaised;

        // project.totalAmountRaised = 0;
        project.withdrawn = true;
        (bool success, ) = payable(msg.sender).call{value: amountRaised}("");
        if (!success) revert TxnFailed();
    }

    function getUserInvestmentForAnIDO(
        uint256 _projectID,
        uint256 _i
    ) external view returns (uint256) {
        if (_projectID > projectsCurrentId || _projectID == 0)
            revert InvalidProjectID();

        Project memory project = projects[_projectID];
        return projectInvestments[_projectID][project.allIDOPartcipants[_i]];
    }

    function getAUserInvestmentForAProject(
        uint256 _projectID,
        address userAddr
    ) external view returns (uint256) {
        if (_projectID > projectsCurrentId || _projectID == 0)
            revert InvalidProjectID();

        return projectInvestments[_projectID][userAddr];
    }

    function cancelProject(uint256 _projectId) external {
        if (msg.sender != launchPadadmin) revert NotLaunchPadAdmin();
        if (_projectId > projectsCurrentId || _projectId == 0)
            revert InvalidProjectID();

        Project storage project = projects[_projectId];
        project.isActive = false;
    }

    function getProjectDetails(
        uint256 _projectID
    ) external view returns (Project memory) {
        if (_projectID > projectsCurrentId || _projectID == 0)
            revert InvalidProjectID();
        return projects[_projectID];
    }

    function getTimeLeft(uint256 projectId) public view returns (uint256) {
        if (projectId > projectsCurrentId || projectId == 0)
            revert InvalidProjectID();

        Project memory project = projects[projectId];

        if (block.timestamp >= project.endTimeInMinutes) {
            return 0; // Project has ended
        } else {
            uint256 timeLeftInSeconds = project.endTimeInMinutes -
                block.timestamp;
            uint256 timeLeftInMinutes = timeLeftInSeconds / 60; // Convert seconds to minutes
            return timeLeftInMinutes;
        }
    }

    function getCurrentProjectID() external view returns (uint256) {
        return projectsCurrentId;
    }

    ///@dev function to get contract balance
    function getContractBal() external view returns (uint256) {
        return address(this).balance;
    }

    ///@dev function to get contract token balance
    function getTokenBalForAParticularProject(
        uint256 projectId
    ) external view returns (uint256) {
        if (projectId > projectsCurrentId || projectId == 0)
            revert InvalidProjectID();

        Project memory project = projects[projectId];
        return IERC20(project.token).balanceOf(address(this));
    }

    receive() external payable {}
}
