# frozen_string_literal: true

require File.dirname(__FILE__) + "/../spec_helper"

describe "Github issue #49" do
  let(:a) { RubyUnits::Unit.new("3 cm^3") }
  let(:b) { RubyUnits::Unit.new(a) }

  it "subtracts a unit properly from one initialized with a unit" do
    expect(b - RubyUnits::Unit.new("1.5 cm^3")).to eq(RubyUnits::Unit.new("1.5 cm^3"))
  end
end

describe "normalize_to_i preserves Float scalar type" do
  it "preserves Float when constructing with a numeric scalar" do
    unit = RubyUnits::Unit.new(400.0, "m^2")
    expect(unit.scalar).to be_a(Float)
    expect(unit.scalar).to eq(400.0)
  end

  it "preserves Float when multiplying a unit by a Float" do
    unit = RubyUnits::Unit.new("m^2") * 400.0
    expect(unit.scalar).to be_a(Float)
    expect(unit.scalar).to eq(400.0)
  end

  it "does not break Float division semantics on extracted scalars" do
    a = RubyUnits::Unit.new("m^2") * 400.0
    b = RubyUnits::Unit.new("m^2") * 1000.0
    expect(a.scalar / b.scalar).to eq(0.4)
  end

  it "normalizes whole Rationals to Integer" do
    unit = RubyUnits::Unit.new(Rational(400, 1), "m^2")
    expect(unit.scalar).to be_a(Integer)
    expect(unit.scalar).to eq(400)
  end

  it "preserves non-whole Rationals" do
    unit = RubyUnits::Unit.new(Rational(3, 2), "m")
    expect(unit.scalar).to be_a(Rational)
    expect(unit.scalar).to eq(Rational(3, 2))
  end
end
