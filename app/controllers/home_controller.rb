class HomeController < ApplicationController
  CACHE_EXPIRES_IN = 30.seconds

  def index
    return redirect_to home_community_appointments_path if current_patient
    return redirect_to first_ubs_or_admin_path if current_user

    @can_register_condition_names = Rails.cache.fetch('home/condition_names', expires_in: CACHE_EXPIRES_IN) do
      condition_names
    end
    @can_schedule_conditions = Rails.cache.fetch('home/schedule_conditions', expires_in: CACHE_EXPIRES_IN) do
      schedule_conditions
    end

    ubs_for_reschedule_ids = Ubs.where(enabled_for_reschedule: true).pluck(:id)
    @reschedule_appointments = Appointment.waiting
                                          .not_scheduled
                                          .where(ubs_id: ubs_for_reschedule_ids, start: from..to)

    reschedule_appointments_ubs_ids = @reschedule_appointments.pluck(:ubs_id).uniq
    @reschedule_appointments_ubs_names = Ubs.where(id: reschedule_appointments_ubs_ids)
                                            .order(:name)
                                            .pluck(:name).join(', ')

    @appointments_any = @can_schedule_conditions.pluck(:doses_count).inject(:+)&.positive?
  end

  protected

  def first_ubs_or_admin_path
    ubs = current_user.ubs.order(:id).first

    ubs ? operator_ubs_appointments_path(ubs) : admin_patients_path
  end

  def condition_names
    Condition.active.can_register.order(:name).pluck(:name)
  end

  def schedule_conditions
    Condition.active.can_schedule.order(:name).includes(:ubs).map do |c|
      {
        name: c.name,
        ubs_names: c.ubs_ids.count == ubs_count ? 'todas unidades' : c.ubs.order(:name).pluck(:name).join(', '),
        doses_count: Appointment.available_doses
                                .where(start: from..to, ubs_id: c.ubs_ids)
                                .count
      }
    end
  end

  def ubs_count
    @ubs_count ||= Ubs.count
  end

  def from
    @from ||= Rails.configuration.x.schedule_from_hours.hours.from_now
  end

  def to
    @to ||= Rails.configuration.x.schedule_up_to_days.days.from_now.end_of_day
  end
end
