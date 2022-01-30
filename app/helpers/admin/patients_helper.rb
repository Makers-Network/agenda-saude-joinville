module Admin
  module PatientsHelper
    LINKS = %i[all locked].freeze

    def admin_nav_links(current_filter, current_search, total_count)
      filter_tabs_links(
        current_filter: current_filter,
        total_count: total_count,
        links: LINKS,
        filters: Admin::PatientsController::FILTERS,
        i18n_scope: :patients,
        path: ->(args) { admin_patients_path(**args) }
      ).tap do |links|
        links << search_link(current_search, total_count, admin_patients_path(search: current_search)) if current_search.present?
      end.join.html_safe # rubocop:disable Rails/OutputSafety
    end

    def register_appointment(patient)
      link_class = 'btn btn-success'

      if patient.doses.any?
        link_class = 'btn btn-success disabled'
      end

      link_to "Registrar dose", new_admin_appointment_path(patient_id: patient.id), class: link_class
    end
  end
end
