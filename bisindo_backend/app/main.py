from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app.services.model_service import predict


app = FastAPI(
    title="BISINDO Mobile API",
    description="Backend API untuk pengenalan bahasa isyarat BISINDO",
    version="1.0.0"
)


class PredictionRequest(BaseModel):
    sequence: list[
        list[float]
    ] = Field(
        min_length=30,
        max_length=30,
        description="Sequence 30 frame dengan 66 fitur per frame"
    )


@app.get("/health")
def health_check():
    return {
        "status": "api siap di gunakan",
        "service": "BISINDO Mobile API"
    }


@app.post("/v1/predict")
def predict_sign(request: PredictionRequest):

    try:
        result = predict(request.sequence)

        return {
            "success": True,
            "prediction": result
        }

    except ValueError as error:
        raise HTTPException(
            status_code=422,
            detail=str(error)
        )