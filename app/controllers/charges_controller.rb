class ChargesController < ApplicationController
  def index
    @charges = Charge.order(created_at: :desc).limit(50)
  end

  def show
    @charge  = Charge.find(params[:id])
    @refunds = @charge.refunds.order(created_at: :desc)
  end
end
