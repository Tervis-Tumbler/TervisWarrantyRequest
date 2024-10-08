function New-WarrantyRequest {
    param (
        [Parameter(ValueFromPipelineByPropertyName)]$ID,
        [Parameter(ValueFromPipelineByPropertyName)]$FirstName,
        [Parameter(ValueFromPipelineByPropertyName)]$LastName,
        [Parameter(ValueFromPipelineByPropertyName)]$BusinessName,
        [Parameter(ValueFromPipelineByPropertyName)]$Address1,
        [Parameter(ValueFromPipelineByPropertyName)]$Address2,
        [Parameter(ValueFromPipelineByPropertyName)]$City,
        [Parameter(ValueFromPipelineByPropertyName)]$State,
        [Parameter(ValueFromPipelineByPropertyName)][String]$PostalCode,
        [Parameter(ValueFromPipelineByPropertyName)][ValidateSet("Residence","Business")]$ResidentialOrBusinessAddress,
        [Parameter(ValueFromPipelineByPropertyName)]$PhoneNumber,
        [Parameter(ValueFromPipelineByPropertyName)]$Email,
        [Parameter(ValueFromPipelineByPropertyName)]$ShippingMSN,
        [Parameter(ValueFromPipelineByPropertyName)]$TrackingNumber,
        [Parameter(ValueFromPipelineByPropertyName)]$Carrier,
        [Parameter(ValueFromPipelineByPropertyName)]$Channel,
        [Parameter(ValueFromPipelineByPropertyName)]$WarrantyLines
    )
    $PSBoundParameters | ConvertFrom-PSBoundParameters
}

function ConvertFrom-FreshDeskTicketToWarrantyRequest {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$Ticket
    )
    process {
        $WarrantyRequestParameters = @{
            ID = $Ticket.ID
            FirstName = $Ticket.custom_fields.cf_first_name
            LastName = $Ticket.custom_fields.cf_last_name
            BusinessName = $Ticket.custom_fields.cf_business_name
            Address1 = $Ticket.custom_fields.cf_address1
            Address2 = $Ticket.custom_fields.cf_address2
            City = $Ticket.custom_fields.cf_city
            State = $Ticket.custom_fields.cf_state
            PostalCode = $Ticket.custom_fields.cf_postalcode
            ResidentialOrBusinessAddress = $Ticket.custom_fields.cf_residenceorbusiness
            PhoneNumber = $Ticket.custom_fields.cf_phonenumber
            Email = $Ticket.custom_fields.cf_email
            ShippingMSN = $Ticket.custom_fields.cf_shipping_msn
            TrackingNumber = $Ticket.custom_fields.cf_tracking_number
            Carrier = $Ticket.custom_fields.cf_shipping_service
            Channel = $Ticket.custom_fields.cf_channel
            WarrantyLines = if ($Ticket.associated_tickets_list) {
                $Ticket.associated_tickets_list |
                ForEach-Object {
                    Get-FreshDeskTicket -ID $_ |
                    ConvertFrom-FreshDeskTicketToWarrantyRequestLine
                }
            }
        } | Remove-HashtableKeysWithEmptyOrNullValues
        New-WarrantyRequest @WarrantyRequestParameters
    }
}

function New-WarrantyRequestLine {
    [CmdletBinding()]
    param ()
    DynamicParam {
        $DynamicParameters = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        New-DynamicParameter -Name ID -ValueFromPipelineByPropertyName -Dictionary $DynamicParameters
        New-DynamicParameter -Name Subject -ValueFromPipelineByPropertyName -Dictionary $DynamicParameters
        New-DynamicParameter -Name DesignName -ValueFromPipelineByPropertyName -Dictionary $DynamicParameters

        New-DynamicParameter -Name Size -ValidateSet (
            Get-WarrantyRequestPropertyValues -PropertyName Size
        ) -Dictionary $DynamicParameters -ValueFromPipelineByPropertyName

        New-DynamicParameter -Name Quantity -Type Int -Dictionary $DynamicParameters

        New-DynamicParameter -Name ManufactureYear -ValidateSet (
            Get-WarrantyRequestPropertyValues -PropertyName ManufactureYear
        ) -Dictionary $DynamicParameters -ValueFromPipelineByPropertyName

        New-DynamicParameter -Name ReturnReason -ValueFromPipelineByPropertyName -ValidateScript {$_ -in $ReturnReasonToIssueTypeMapping.Keys} -Dictionary $DynamicParameters
        $DynamicParameters
    }
    process {
        $PSBoundParameters | ConvertFrom-PSBoundParameters
    }
}

function ConvertFrom-FreshDeskTicketToWarrantyRequestLine {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$Ticket
    )
    process {
        $ReturnReason = $ReturnReasonToIssueTypeMapping.keys |
        Where-Object {
            $ReturnReasonToIssueTypeMapping.$_.cf_issue_description -eq $Ticket.custom_fields.cf_issue_description
        } |
        Where-Object {
            $ReturnReasonToIssueTypeMapping.$_.cf_issue_subcode -eq $Ticket.custom_fields.cf_issue_subcode
        }

        $WarrantyRequestLineParameters = @{
            ID = $Ticket.ID
            Subject = $Ticket.subject
            Size = $Ticket.custom_fields.cf_size
            Quantity = $Ticket.custom_fields.cf_quantitynumber
            ManufactureYear = $Ticket.custom_fields.cf_mfd_year
            ReturnReason = $ReturnReason
        } | Remove-HashtableKeysWithEmptyOrNullValues
        New-WarrantyRequestLine @WarrantyRequestLineParameters
    }
}

function New-WarrantyParentTicket {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$WarrantyRequest
    )
    process {
        $RequestorIDParameter = if (-not $WarrantyRequest.Email -and -not $WarrantyRequest.PhoneNumber) {
            $FreshDeskContact = New-FreshDeskContact -name "$FirstName $LastName" -phone "555-555-5555"
            @{requester_id = $FreshDeskContact.ID}
        } else {
            @{}
        }

        $WarrantyParentFreshDeskTicketParameter = $WarrantyRequest |
        New-WarrantyParentFreshDeskTicketParameter
        
        $WarrantyParentTicket = New-FreshDeskTicket @WarrantyParentFreshDeskTicketParameter @RequestorIDParameter
        $WarrantyParentTicket
        if ($WarrantyRequest.WarrantyLines) {
            $WarrantyRequest.WarrantyLines | 
            New-WarrantyChildTicket -WarrantyParentTicket $WarrantyParentTicket
        }
    }
}

function New-WarrantyChildTicket {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$WarrantyLine,
        [Parameter(Mandatory,ParameterSetName="WarrantyParentTicketID")]$WarrantyParentTicketID,
        [Parameter(Mandatory,ParameterSetName="WarrantyParentTicket")]$WarrantyParentTicket
    )
    process {
        if (-not $WarrantyParentTicket) {
            $WarrantyParentTicket = Get-FreshDeskTicket -ID $WarrantyParentTicketID
        } 

        $WarrantyRequest = $WarrantyParentTicket | 
        ConvertFrom-FreshDeskTicketToWarrantyRequest

        $ParametersFromWarantyParent = $WarrantyRequest | 
        Select-Object -Property Email, FirstName, LastName | 
        ConvertTo-HashTable |
        Remove-HashtableKeysWithEmptyOrNullValues

        $WarrantyChildFreshDeskTicketParameter = $WarrantyLine |
        New-WarrantyChildFreshDeskTicketParameter @ParametersFromWarantyParent -ParentID $WarrantyParentTicketID

        New-FreshDeskTicket @WarrantyChildFreshDeskTicketParameter -requester_id $WarrantyParentTicket.requester_id
    }
}

function New-WarrantyParentFreshDeskTicketParameter {
    param (
        [Parameter(ValueFromPipelineByPropertyName)]$FirstName,
        [Parameter(ValueFromPipelineByPropertyName)]$LastName,
        [Parameter(ValueFromPipelineByPropertyName)]$BusinessName,
        [Parameter(ValueFromPipelineByPropertyName)]$Address1,
        [Parameter(ValueFromPipelineByPropertyName)]$Address2,
        [Parameter(ValueFromPipelineByPropertyName)]$City,
        [Parameter(ValueFromPipelineByPropertyName)]$State,
        [Parameter(ValueFromPipelineByPropertyName)]$PostalCode,
        [Parameter(ValueFromPipelineByPropertyName)][ValidateSet("Residence","Business")]$ResidentialOrBusinessAddress,
        [Parameter(ValueFromPipelineByPropertyName)]$PhoneNumber,
        [Parameter(ValueFromPipelineByPropertyName)]$Email,
        [Parameter(ValueFromPipelineByPropertyName)]$Channel,
        [Parameter(ValueFromPipelineByPropertyName)]$WarrantyLines
    )
    process {
        @{
            priority = 1
            email = $Email
            phone = $PhoneNumber
            name = "$FirstName $LastName"
		    source = 2
		    status = 2
		    type = "Warranty Parent"
		    subject = "MFL for " + $FirstName + " " + $LastName + " " + (get-date).tostring("G")
		    description = "Warranty Request"
		    custom_fields = @{
		    	cf_first_name = $FirstName
                cf_last_name = $LastName
                cf_business_name = $BusinessName
		        cf_address1 = $Address1
		        cf_address2 = $Address2
                cf_city = $City
		        cf_state = $State
		        cf_postalcode = $PostalCode
		        cf_residenceorbusiness = $ResidentialOrBusinessAddress
                cf_phonenumber = $PhoneNumber
                cf_email = $Email
                cf_source = "Warranty Return Form Internal"
                cf_channel = $Channel
		    } | Remove-HashtableKeysWithEmptyOrNullValues
        } | Remove-HashtableKeysWithEmptyOrNullValues
    }
}

$ReturnReasonToIssueTypeMapping = [ordered]@{
    "Cracked" = @{ #"02.110.01"
        cf_issue_type = "02-Product"
        cf_issue_description = ".110 Cracked"
        cf_issue_subcode = ".01-Cracked at Weld"
    }
    "Cracked not at Weld" = @{ #"02.110.03"
        cf_issue_type = "02-Product"
        cf_issue_description = ".110 Cracked"
        cf_issue_subcode = ".03-No at weld"
    }
    "Cracked Stress Cracks" = @{ #"02.110.02"
        cf_issue_type = "02-Product"
        cf_issue_description = ".110 Cracked"
        cf_issue_subcode = ".02-Stress Cracks"
    }
    "Decoration Fail" = @{ #"02.600.01"
        cf_issue_type = "02-Product"
        cf_issue_description = ".600 Decoration"
        cf_issue_subcode = ".01-Damaged"
    }
    "Film" = @{ #"02.200.02"
        cf_issue_type = "02-Product"
        cf_issue_description = ".200 Surface"
        cf_issue_subcode = ".02-Film/Stains"
    }
    "Heat Distortion" = @{ #"02.900.00"
        cf_issue_type = "02-Product"
        cf_issue_description = ".900 Deformed"
        cf_issue_subcode = ".01-Deformed"
    }
    "Stainless Defect" = @{ #"02.090.95"
        cf_issue_type = "02-Product"
        cf_issue_description = ".090 Supplier"
        cf_issue_subcode = ".95-Poor Thermal Performance"
    }
    "Seal Failure" = @{ #"02.100.01"
        cf_issue_type = "02-Product"
        cf_issue_description = ".100 - Weld/Seal"
        cf_issue_subcode = ".01-Tumbler in two pieces"
    }
    "Sunscreen" = @{ #"02.200.03"
        cf_issue_type = "02-Product"
        cf_issue_description = ".200 Surface"
        cf_issue_subcode = ".03-Sunscreen"
    }
}

function Get-ReturnReasonIssueTypeMapping {
    $ReturnReasonToIssueTypeMapping
}

function New-WarrantyChildFreshDeskTicketParameter {
    param (
        [Parameter(ValueFromPipelineByPropertyName)]$DesignName,
        [Parameter(ValueFromPipelineByPropertyName)]$Size,
        [Parameter(ValueFromPipelineByPropertyName)]$Quantity,
        [Parameter(ValueFromPipelineByPropertyName)]$ManufactureYear,
        [Parameter(ValueFromPipelineByPropertyName)]$ReturnReason,
        $Email,
        $FirstName,
        $LastName,
        [Int]$ParentID
    )
    process {
        $IssueTypeFields = $ReturnReasonToIssueTypeMapping.$ReturnReason
        @{
            priority = 1
            email = $Email
            source = 2
            status = 5
            type = "Warranty Child"
            subject = "$DesignName $Size for $FirstName $LastName"
            description = "Warranty Child Request for Parent Ticket : $ParentID"
            parent_id = $ParentID
            custom_fields = (
                @{
                    cf_size = $Size
                    cf_quantitynumber = $Quantity
                    cf_mfd_year = $ManufactureYear
                    cf_source = "Warranty Return Form Internal"
                    cf_parentticketid = "$ParentID"
                } + $IssueTypeFields
            ) | Remove-HashtableKeysWithEmptyOrNullValues
        } | Remove-HashtableKeysWithEmptyOrNullValues
    }
}

$WarrantyPropertyToTicketPropertyNameMapping = @{
    Size = "cf_size"
    Quantity = "cf_quantitynumber"
    ManufactureYear = "cf_mfd_year"
    ResidentialOrBusinessAddress = "cf_residenceorbusiness"
    State = "cf_state"
    Channel = "cf_channel"
}

function Get-WarrantyRequestPropertyValues {
    param (
        [ValidateScript({$_ -in $WarrantyPropertyToTicketPropertyNameMapping.Keys})]
        [Parameter(Mandatory)]
        $PropertyName
    )
    $TicketPropertyName = $WarrantyPropertyToTicketPropertyNameMapping.$PropertyName

    $Choices = Get-TervisFreshDeskTicketField |
    Where-Object Name -EQ $TicketPropertyName |
    Select-Object -ExpandProperty Choices

    if ($Choices.count) {
        $Choices |
        ConvertTo-Json |
        ConvertFrom-Json
    } else {
        $Choices.psobject.Properties.name |
        ConvertTo-Json |
        ConvertFrom-Json
    }

    #$TypeNameOfChoice = (
    #    $Choices |
    #    Select-Object -First 1
    #).gettype() |
    #Select-Object -ExpandProperty FullName
    #
    #$TypeOfChoice = [type]$TypeNameOfChoice
    #$ArrayTypeOfChoice = $TypeOfChoice.MakeArrayType()
    #$Choices -as $ArrayTypeOfChoice
}

function Get-WarrantyRequest {
    param (
        [Parameter(Mandatory)]$FreshDeskWarrantyParentTicketID
    )
    Get-FreshDeskTicket -ID $FreshDeskWarrantyParentTicketID |
    Where-Object {-Not $_.Deleted} |
    ConvertFrom-FreshDeskTicketToWarrantyRequest
}