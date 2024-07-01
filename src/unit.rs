use crate::Square;
use serde::{Serialize, Serializer};

#[derive(Copy, Clone)]
pub enum Unit {
    None,
    OrcCommander,
    OrcSoldier,
}

impl Unit {
    pub fn is_commander(&self) -> bool {
        match self {
            Unit::OrcCommander => true,
            _ => false,
        }
    }

    pub fn default_square(&self) -> Square {
        match self {
            Unit::None => Square {
                unit: Unit::None,
                health_points: 0,
                captured: false,
                move_credits: 0,
            },
            Unit::OrcCommander => Square {
                unit: Unit::OrcCommander,
                health_points: 58,
                captured: false,
                move_credits: 5,
            },
            Unit::OrcSoldier => Square {
                unit: Unit::OrcSoldier,
                health_points: 12,
                captured: false,
                move_credits: 5,
            },
        }
    }
}

impl TryFrom<u64> for Unit {
    type Error = String;

    fn try_from(value: u64) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Unit::None),
            1 => Ok(Unit::OrcCommander),
            2 => Ok(Unit::OrcSoldier),
            _ => Err("Invalid unit id.".to_string()),
        }
    }
}

impl Serialize for Unit {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_u64(self.into())
    }
}

impl From<&Unit> for u64 {
    fn from(value: &Unit) -> Self {
        match value {
            Unit::None => 0,
            Unit::OrcCommander => 1,
            Unit::OrcSoldier => 2,
        }
    }
}

#[derive(Copy, Clone)]
pub enum Commander {
    Orc,
}

impl From<Commander> for Unit {
    fn from(value: Commander) -> Self {
        match value {
            Commander::Orc => Unit::OrcCommander,
        }
    }
}
