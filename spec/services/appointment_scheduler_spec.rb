require 'rails_helper'

# Need to disable transactional tests because AppointmentScheduler opens a
# transaction, which will be nested within RSpec transaction, causing the
# :isolation option to fail as it's only allowed for top-level transactions
RSpec.describe AppointmentScheduler, type: :service, use_transactional_tests: false do
  subject(:scheduler) { described_class.new }

  let!(:ubs) { create(:ubs, active: true) }
  let(:patient) { create(:patient, cpf: '29468604004', main_ubs: ubs) }
  let(:start_time) { '2020-01-01 12:40:00 -0300' }
  let(:time) { Time.zone.local('2020-01-01') }
  let(:quick_schedule_args) { { patient: patient, ubs_id: nil, start: 1.minute.from_now...3.days.from_now } }
  let(:specific_ubs_args) { { patient: patient, ubs_id: ubs.id, start: 1.minute.from_now...3.days.from_now } }

  before { travel_to time }
  after { travel_back }

  before do
    allow(patient).to receive(:can_schedule?).and_return(true)
  end

  describe 'when ubs is inactive' do
    before do
      ubs.update!(active: false)
    end

    it 'returns no slots result with no changes to appointments' do
      expect do
        expect(
          scheduler.schedule(**quick_schedule_args)
        ).to eq([AppointmentScheduler::NO_SLOTS])
      end.not_to(change { Appointment.order(:id).map(&:attributes) })
    end
  end

  describe 'when all slots were taken' do
    before do
      create_list(
        :appointment,
        3,
        start: start_time,
        ubs: ubs,
        patient: create(:patient)
      )
    end

    it 'returns no slots result with no changes to appointments' do
      expect do
        expect(
          scheduler.schedule(**quick_schedule_args)
        ).to eq([AppointmentScheduler::NO_SLOTS])
      end.not_to(change { Appointment.order(:id).map(&:attributes) })
    end
  end

  describe 'when patient cannot schedule' do
    before do
      allow(patient).to receive(:can_schedule?).and_return(false)
    end

    it 'returns conditions unmet result with no changes to appointments' do
      expect do
        expect(
          scheduler.schedule(patient: patient, ubs_id: nil, start: 1.minute.from_now...3.days.from_now)
        ).to eq([described_class::CONDITIONS_UNMET])
      end.not_to(change { Appointment.order(:id).map(&:attributes) })
    end
  end

  describe 'when start time is past allowed window' do
    let(:past_max_schedule_time_ahead) { Rails.configuration.x.schedule_up_to_days.days.from_now.end_of_day + 1.minute}

    before do
      create(:appointment, start: Rails.configuration.x.schedule_from_hours.hours.from_now + 1.minute, ubs: ubs, patient_id: nil)
    end

    it 'returns no slots result with no changes to appointments' do
      expect do
        expect(
          scheduler.schedule(patient: patient, ubs_id: nil,
                             start: past_max_schedule_time_ahead..(past_max_schedule_time_ahead + 1.year))
        ).to eq([AppointmentScheduler::NO_SLOTS])
      end.not_to(change { Appointment.order(:id).map(&:attributes) })
    end
  end

  describe 'when there are free time slots' do
    before do
      create_list(
        :appointment,
        3,
        start: start_time,
        ubs: ubs,
        patient: nil
      )
    end

    it 'updates exactly one appointment' do
      expect do
        expect(scheduler.schedule(**quick_schedule_args))
          .to eq([described_class::SUCCESS, Appointment.find_by(patient_id: patient.id)])
      end.to change { Appointment.where(patient_id: nil).count }.by(-1)
    end
  end
end
