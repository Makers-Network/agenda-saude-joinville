class Appointment < ApplicationRecord
  belongs_to :patient, optional: true
  belongs_to :ubs
  has_one :dose, dependent: :restrict_with_exception
  has_one :follow_up_for_dose,
          class_name: 'Dose',
          foreign_key: :follow_up_appointment_id,
          dependent: :restrict_with_exception,
          inverse_of: :follow_up_appointment

  scope :today, -> { where(start: Time.zone.now.all_day) }

  scope :checked_in, -> { where.not(check_in: nil) }
  scope :not_checked_in, -> { where(check_in: nil) }

  scope :checked_out, -> { where.not(check_out: nil) }
  scope :not_checked_out, -> { where(check_out: nil) }

  scope :scheduled, -> { where.not(patient_id: nil) }

  scope :future, -> { where(arel_table[:start].gt(Time.zone.now)) }

  scope :not_scheduled, -> { where(patient_id: nil) }

  scope :active, -> { where(active: true) }
  scope :suspended, -> { where(active: false) }

  # Where the UBS is active
  # Needs to be left_joins due to query on AppointmentScheduler#open_times_per_ubs, to allow us to get proper results
  # when used with DISTINCT
  scope :active_ubs, -> { left_joins(:ubs).where(Ubs.arel_table[:active].eq(true)) }

  # Active and not checked in or out (regardless if in the past or future)
  scope :waiting, -> { not_checked_in.not_checked_out }

  scope :available_doses, lambda {
    active_ubs
      .active
      .waiting
      .not_scheduled
  }

  scope :search_for, lambda { |text|
    joins(:patient)
      .where(
        Patient.arel_table[:cpf]
               .eq(Patient.parse_cpf(text)) # Search for CPF without . and -
               .or(Patient.arel_table[:name].matches("%#{text.strip}%"))
      )
  }

  def in_allowed_check_in_window?
    start > Time.zone.now.beginning_of_day && start < Time.zone.now.end_of_day
  end

  # Is this appointment active?
  def active?
    active
  end

  # Is this appointment suspended?
  def suspended?
    !active?
  end

  # Have the patient checked out?
  def checked_out?
    check_out.present?
  end

  # Have the patient checked in?
  def checked_in?
    check_in.present?
  end

  # Is this appointment still waiting for the patient to check in?
  def waiting?
    !checked_in?
  end

  def state
    return :suspended if suspended?
    return :checked_out if checked_out?
    return :checked_in if checked_in?

    :waiting
  end

  # Applied, to be applied, or likely sequence number
  def dose_sequence_number
    return nil unless patient_id

    dose&.sequence_number || follow_up_for_dose&.next_sequence_number || 1
  end

  # Applied, or to be applied vaccine
  def dose_vaccine
    dose&.vaccine || follow_up_for_dose&.vaccine
  end

  def can_check_in?
    patient_id.present? && !checked_in? && !checked_out? && active?
  end

  def can_undo_check_in?
    can_check_out?
  end

  def can_check_out?
    patient_id.present? && checked_in? && !checked_out? && active?
  end

  def can_undo_check_out?
    patient_id.present? && checked_in? && checked_out? && active? &&
      (!dose.follow_up_appointment || dose.follow_up_appointment.can_check_in?)
  end

  def can_suspend?
    !checked_in? && !checked_out? && active?
  end

  def can_activate?
    !active?
  end

  # Can only remove patient for 1st dose, can't remove for 2nd dose and up (due to complications on follow up process)
  def can_remove_patient?
    patient_id.present? && can_check_in? && dose_sequence_number == 1
  end

  # We need to disable this transaction on test env due to how RSpec and System tests run
  def self.isolated_transaction(&block)
    return yield if Rails.env.test?

    transaction(isolation: :repeatable_read, &block)
  end
end
