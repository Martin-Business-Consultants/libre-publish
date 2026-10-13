# frozen_string_literal: true

# A reported block allowed (its source added to that policy's directive), or
# dismissed (left blocked, and out of the list).
class Settings::SecurityPolicies::AllowancesController < Settings::BaseController
  requires_capability "settings:write", only: [:create, :destroy]

  def create
    report = CspReport.find(params[:id])
    if SecurityPolicy.allow(report.surface, report.directive, report.blocked)
      report.update!(dismissed: true)
      Event.record("settings.security_policy_updated")
      redirect_to settings_security_policy_path(anchor: "reports"), notice: "#{report.blocked} allowed for #{report.directive} on the #{report.surface}"
    else
      redirect_to settings_security_policy_path(anchor: "reports"), alert: "#{report.directive} can't be widened on the #{report.surface} from here"
    end
  end

  def destroy
    CspReport.find(params[:id]).update!(dismissed: true)
    redirect_to settings_security_policy_path(anchor: "reports"), notice: "Dismissed"
  end
end
