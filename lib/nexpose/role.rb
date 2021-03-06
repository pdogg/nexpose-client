module Nexpose

  # Constants
  module Privilege

    module Global
      CREATE_REPORTS = 'CreateReports'
      CONFIGURE_GLOBAL_SETTINGS = 'ConfigureGlobalSettings'
      MANAGE_SITES = 'ManageSites'
      MANAGE_ASSET_GROUPS = 'ManageAssetGroups'
      MANAGE_DYNAMIC_ASSET_GROUPS = 'ManageDynamicAssetGroups'
      MANAGE_SCAN_TEMPLATES = 'ManageScanTemplates'
      MANAGE_REPORT_TEMPLATES = 'ManageReportTemplates'
      GENERATE_RESTRICTED_REPORTS = 'GenerateRestrictedReports'
      MANAGE_SCAN_ENGINES = 'ManageScanEngines'
      SUBMIT_VULN_EXCEPTIONS = 'SubmitVulnExceptions'
      APPROVE_VULN_EXCEPTIONS = 'ApproveVulnExceptions'
      DELETE_VULN_EXCEPTIONS = 'DeleteVulnExceptions'
      CREATE_TICKETS = 'CreateTickets'
      CLOSE_TICKETS = 'CloseTickets'
      TICKET_ASSIGNEE = 'TicketAssignee'
      ADD_USERS_TO_SITE = 'AddUsersToSite'
      ADD_USERS_TO_GROUP = 'AddUsersToGroup'
      ADD_USERS_TO_REPORT = 'AddUsersToReport'
      MANAGE_POLICIES = 'ManagePolicies'
    end

    module Site
      VIEW_ASSET_DATA = 'ViewAssetData'  # NOTE Duplicated between Site and AssetGroup
      CONFIGURE_ALERTS = 'ConfigureAlerts'
      CONFIGURE_CREDENTIALS = 'ConfigureCredentials'
      CONFIGURE_ENGINES = 'ConfigureEngines'
      CONFIGURE_SCAN_TEMPLATES = 'ConfigureScanTemplates' 
      CONFIGURE_SCHEDULE_SCANS = 'ConfigureScheduleScans' 
      CONFIGURE_SITE_SETTINGS = 'ConfigureSiteSettings'
      CONFIGURE_TARGETS = 'ConfigureTargets'
      MANUAL_SCANS = 'ManualScans'
      PURGE_DATA = 'PurgeData'
    end

    module AssetGroup
      CONFIGURE_ASSETS = 'ConfigureAssets'
      VIEW_ASSET_DATA = 'ViewAssetData'  # NOTE Duplicated between Site and AssetGroup
    end
  end

  class Connection
    include XMLUtils

    # Returns a summary list of all roles.
    #
    def role_listing
      xml = make_xml('RoleListingRequest')
      r = execute(xml, '1.2')
      roles = []
      if r.success
        r.res.elements.each('RoleListingResponse/RoleSummary') do |summary|
          roles << RoleSummary::parse(summary)
        end
      end
      roles
    end

    alias_method :roles, :role_listing

    def role_delete(role, scope = Scope::SILO)
      xml = %Q(<RoleDeleteRequest session-id="#{@session_id}">)
      xml << %Q(<Role name="#{role}" scope="#{scope}"/>)
      xml << '</RoleDeleteRequest>' 
      response = execute(xml, '1.2')
      response.success
    end

    alias_method :delete_role, :role_delete
  end

  # Role summary object encapsulating information about a role.
  #
  class RoleSummary

    # The short name of the role. Must be unique.
    attr_accessor :name

    # The full name of the role. Must be unique.
    attr_accessor :full_name

    # The unique identifier of the role.
    attr_accessor :id

    # A description of the role.
    attr_accessor :description

    # Whether or not the role is enabled.
    attr_accessor :enabled

    # Specifies if the role has global or silo scope.
    # @see Nexpose::Scope
    attr_accessor :scope

    def initialize(name, full_name, id, description, enabled = true, scope = Scope::SILO)
      @name, @full_name, @id, @description, @enabled, @scope = name, full_name, id, description, enabled, scope
    end

    def self.parse(xml)
      new(xml.attributes['name'],
          xml.attributes['full-name'],
          xml.attributes['id'].to_i,
          xml.attributes['description'],
          xml.attributes['enabled'] == 'true',
          xml.attributes['scope'])
    end
  end

  class Role < RoleSummary

    # Constants, mapping UI terms to role names expected by API.

    GLOBAL_ADMINISTRATOR = 'global-admin'
    ASSET_OWNER = 'system-admin'
    SECURITY_MANAGER = 'security-manager'
    SITE_OWNER = 'site-admin'
    USER = 'user'

    # Array of all privileges which are enabled for this role.
    # Note: Although the underlying XML has different requirements, this only checks for presence.
    # @see Nexpose::Privilege
    attr_accessor :privileges

    # Flag to track whether this role exists already on the Nexpose console.
    # Flag determines behavior of #save method.
    attr_accessor :existing

    def initialize(name, full_name, id, enabled = true, scope = Scope::SILO)
      @name, @full_name, @id, @enabled, @scope = name, full_name, id, enabled, scope
      @privileges = []
    end

    # Retrieve a detailed description of a single role.
    #
    # @param [Connection] nsc Nexpose connection.
    # @param [String] name The short name of the role.
    # @param [String] scope Whether the role has global or silo scope. @see Nexpose::Scope
    #   Scope doesn't appear to be required when requesting installed roles.
    # @return [Role] requested role.
    #
    def self.load(nsc, name, scope = Scope::SILO)
      xml = %Q(<RoleDetailsRequest session-id="#{nsc.session_id}">)
      xml << %Q(<Role name="#{name}" scope="#{scope}"/>)
      xml << '</RoleDetailsRequest>'

      response = APIRequest.execute(nsc.url, xml, '1.2')
      if response.success
        elem = REXML::XPath.first(response.res, 'RoleDetailsResponse/Role/')
        parse(elem)
      end
    end

    alias_method :get, :load

    # Create or save a Role to the Nexpose console.
    #
    # @param [Connection] nsc Nexpose connection.
    #
    def save(nsc)
      if @existing
        xml = %Q(<RoleUpdateRequest session-id="#{nsc.session_id}">)
        xml << to_xml
        xml << '</RoleUpdateRequest>'
      else
        xml = %Q(<RoleCreateRequest session-id="#{nsc.session_id}">)
        xml << to_xml
        xml << '</RoleCreateRequest>'
      end

      response = APIRequest.execute(nsc.url, xml, '1.2')
      xml = REXML::XPath.first(response.res, 'RoleCreateResponse')
      @id = xml.attributes['id'].to_i
      @existing = true
      response.success
    end

    # Copy an existing Role to build a new role off of it.
    # Role will not have a valid name or full_name, so they will need to be provided before saving.
    #
    # @param [Connection] nsc Nexpose connection.
    # @param [String] name The short name of the role which you wish to copy.
    # @param [String] scope Whether the role has global or silo scope. @see Nexpose::Scope
    # @return [Role] requested role.
    #
    def self.copy(nsc, name, scope = Scope::SILO)
      role = load(nsc, name, scope)
      role.name = role.full_name = nil
      role.id = -1
      role.existing = false
      role
    end

    # Remove this role from the Nexpose console.
    #
    # @param [Connection] nsc Nexpose connection.
    #
    def delete(nsc)
      xml = %Q(<RoleDeleteRequest session-id="#{nsc.session_id}">)
      xml << %Q(<Role name="#{@name}" scope="#{@scope}"/>)
      xml << '</RoleDeleteRequest>' 
      response = APIRequest.execute(nsc.url, xml, '1.2')
      response.success
    end

    def self.parse(xml)
      role = new(xml.attributes['name'],
                 xml.attributes['full-name'],
                 xml.attributes['id'].to_i,
                 xml.attributes['enabled'] == 'true',
                 xml.attributes['scope'])

      role.description = REXML::XPath.first(xml, 'Description').text
      role.existing = true

      # Only grab enabled privileges.
      xml.elements.each("GlobalPrivileges/child::*[@enabled='true']") do |privilege|
        role.privileges << privilege.name
      end
      xml.elements.each("SitePrivileges/child::*[@enabled='true']") do |privilege|
        role.privileges << privilege.name
      end
      xml.elements.each("AssetGroupPrivileges/child::*[@enabled='true']") do |privilege|
        role.privileges << privilege.name
      end
      role
    end

    def to_xml
      xml = %Q(<Role name="#{@name}" full-name="#{@full_name}")
      xml << %Q( enabled="#{(enabled ? 'true' : 'false')}")
      xml << %Q( scope="#{@scope}">)
      xml << %Q(<Description>#{@description}</Description>)

      xml << '<SitePrivileges>'
      Privilege::Site::constants.each do |field|
        as_s = Privilege::Site.const_get(field)
        enabled = (privileges.member? as_s) ? 'true' : 'false'
        xml << %Q(<#{as_s} enabled="#{enabled}"/>)
      end
      xml << '</SitePrivileges>'

      xml << '<AssetGroupPrivileges>'
      Privilege::AssetGroup::constants.each do |field|
        as_s = Privilege::AssetGroup.const_get(field)
        enabled = (privileges.member? as_s) ? 'true' : 'false'
        xml << %Q(<#{as_s} enabled="#{enabled}"/>)
      end
      xml << '</AssetGroupPrivileges>'

      xml << '<GlobalPrivileges>'
      Privilege::Global::constants.each do |field|
        as_s = Privilege::Global.const_get(field)
        enabled = (privileges.member? as_s) ? 'true' : 'false'
        xml << %Q(<#{as_s} enabled="#{enabled}"/>)
      end
      xml << '</GlobalPrivileges>'

      xml << '</Role>'
      xml
    end
  end
end
